import Combine
import CoreAudio
import Foundation

/// 單一 App 的路由設定。以 bundle ID 為鍵持久化，App 重開後自動套用。
public struct RouteSettings: Codable, Hashable, Sendable {
    /// nil 代表「跟隨系統輸出」。
    public var outputDeviceUID: String?
    public var volume: Float
    public var muted: Bool
    public var balance: Float
    /// 給 UI 顯示用的名字（行程沒在跑的時候還是要能列出來）。
    public var displayName: String

    public init(
        outputDeviceUID: String? = nil,
        volume: Float = 1,
        muted: Bool = false,
        balance: Float = 0,
        displayName: String = ""
    ) {
        self.outputDeviceUID = outputDeviceUID
        self.volume = volume
        self.muted = muted
        self.balance = balance
        self.displayName = displayName
    }

    /// 全部都是預設值時就不需要建立 tap，讓音訊走系統原本的路徑。
    public var isPassthrough: Bool {
        outputDeviceUID == nil && volume == 1 && !muted && balance == 0
    }
}

/// 一個播放源在 UI 上的完整狀態。
public struct RoutedApp: Identifiable, Hashable, Sendable {
    public let key: String
    /// 目前正在跑的行程群組；App 沒在跑時為 nil（設定仍會保留）。
    public let group: AudioProcessGroup?
    public var settings: RouteSettings
    /// 這條路由目前是否真的有 tap 在跑。
    public let isActive: Bool
    /// 建立失敗時的訊息。
    public let error: String?

    public var id: String { key }
    public var name: String { group?.name ?? settings.displayName }
    public var isRunning: Bool { group != nil }
    public var isPlaying: Bool { group?.isPlaying ?? false }
    public var isSystemProcess: Bool { group?.isSystemProcess ?? false }
    /// 這個播放源底下有幾個發聲行程（瀏覽器之類會有獨立的音訊 helper）。
    public var processCount: Int { group?.processes.count ?? 0 }
}

/// 統籌所有路由：追蹤行程與裝置變動、建立/銷毀引擎、存讀設定。
@MainActor
public final class RouterManager: ObservableObject {
    /// 所有播放源（含目前沒在出聲的）。系統程序是否納入由 `showsSystemProcesses` 決定。
    @Published public private(set) var apps: [RoutedApp] = []
    @Published public private(set) var outputDevices: [AudioDevice] = []
    @Published public private(set) var inputDevices: [AudioDevice] = []
    @Published public private(set) var defaultOutput: AudioDevice?
    @Published public private(set) var defaultInput: AudioDevice?
    @Published public var lastError: String?

    /// 是否把系統守護程序（CoreSpeech、audiomxd…）也列出來。
    /// 預設關閉：機器上通常有三十幾個這種行程，全開會把真正的 App 淹掉。
    @Published public var showsSystemProcesses = false {
        didSet {
            guard oldValue != showsSystemProcesses else { return }
            rebuildSnapshot()
            // 監看範圍跟著顯示範圍走，打開系統程序後它們的播放狀態也要會動。
            updatePlaybackObservers()
        }
    }

    private var settings: [String: RouteSettings] = [:]
    private var engines: [String: RouteEngine] = [:]
    private var engineErrors: [String: String] = [:]
    /// 每個引擎目前實際綁定的輸出裝置與行程，用來判斷是否需要重建。
    private var engineTargets: [String: (deviceUID: String, processIDs: [AudioObjectID])] = [:]
    /// 最近一次掃描到的播放源。每輪 refresh 算一次，避免重複查詢 Core Audio。
    private var currentGroups: [AudioProcessGroup] = []

    private var processObserver: Any?
    private var deviceObserver: Any?
    /// 播放狀態的監聽器，只掛在清單上會顯示的 App。
    private var playbackObserver: AudioProcesses.PlaybackObserver?
    /// 目前監看中的行程，用來判斷是否需要重掛。
    private var watchedPlaybackIDs: [AudioObjectID] = []
    private let storeURL: URL

    public init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? RouterManager.defaultStoreURL()
        RouteEngine.cleanupOrphanedAggregates()
        loadSettings()
        refresh()

        processObserver = AudioProcesses.observeChanges(queue: .main) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        deviceObserver = AudioDevices.observeChanges(queue: .main) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - 對外操作

    public func setOutputDevice(_ uid: String?, forKey key: String) {
        mutate(key) { $0.outputDeviceUID = uid }
    }

    public func setVolume(_ volume: Float, forKey key: String) {
        let clamped = max(0, min(1, volume))
        // 只調音量時走即時路徑，不必重建整條鏈。
        engines[key]?.volume = clamped
        mutate(key) { $0.volume = clamped }
    }

    public func setMuted(_ muted: Bool, forKey key: String) {
        engines[key]?.isMuted = muted
        mutate(key) { $0.muted = muted }
    }

    public func setBalance(_ balance: Float, forKey key: String) {
        let clamped = max(-1, min(1, balance))
        engines[key]?.balance = clamped
        mutate(key) { $0.balance = clamped }
    }

    /// 把某個播放源恢復成完全跟隨系統。
    public func reset(key: String) {
        settings[key]?.outputDeviceUID = nil
        settings[key]?.volume = 1
        settings[key]?.muted = false
        settings[key]?.balance = 0
        saveSettings()
        reconcile()
        rebuildSnapshot()
    }

    /// 移除一筆已記住但目前沒在跑的設定。
    public func forget(key: String) {
        settings.removeValue(forKey: key)
        teardownEngine(forKey: key)
        saveSettings()
        rebuildSnapshot()
    }

    public func setSystemDefaultOutput(_ device: AudioDevice) {
        do { try AudioDevices.setDefaultOutput(device) } catch { lastError = "\(error)" }
        refresh()
    }

    public func setSystemDefaultInput(_ device: AudioDevice) {
        do { try AudioDevices.setDefaultInput(device) } catch { lastError = "\(error)" }
        refresh()
    }

    public func settings(forKey key: String) -> RouteSettings {
        settings[key] ?? RouteSettings()
    }

    // MARK: - 內部

    private func mutate(_ key: String, _ body: (inout RouteSettings) -> Void) {
        var current = settings[key] ?? RouteSettings(displayName: displayName(forKey: key))
        if current.displayName.isEmpty { current.displayName = displayName(forKey: key) }
        body(&current)
        settings[key] = current
        saveSettings()
        reconcile()
        rebuildSnapshot()
    }

    private func displayName(forKey key: String) -> String {
        currentGroups.first { $0.key == key }?.name
            ?? settings[key]?.displayName
            ?? key
    }

    public func refresh() {
        outputDevices = AudioDevices.outputs()
        inputDevices = AudioDevices.inputs()
        defaultOutput = AudioDevices.defaultOutput()
        defaultInput = AudioDevices.defaultInput()
        currentGroups = AudioProcesses.groups()
        reconcile()
        rebuildSnapshot()
        updatePlaybackObservers()
        writeDiagnosticSnapshot()
    }

    /// 只對清單上顯示得出來的 App 監看播放狀態。
    ///
    /// 系統背景程序有二十幾個，平常根本不顯示，沒必要為了它們各掛一個監聽器；
    /// 使用者打開齒輪把它們叫出來時才一併納入。
    private func updatePlaybackObservers() {
        let ids = currentGroups
            .filter { showsSystemProcesses || !$0.isSystemProcess }
            .flatMap(\.processObjectIDs)
            .sorted()

        // 監看對象沒變就不動，否則每次 refresh 都拆掉重掛。
        guard ids != watchedPlaybackIDs else { return }
        watchedPlaybackIDs = ids

        // 先釋放舊的：它的 deinit 會把先前的監聽器移除。
        playbackObserver = nil
        playbackObserver = AudioProcesses.observePlaybackState(of: ids, queue: .main) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// 每次 refresh 覆寫一份現況到 ~/Library/Logs/SoundRouter-status.txt。
    /// 選單列 App 沒有 stdout 可看，出問題時這是唯一能對照「App 到底看到什麼」的依據。
    private func writeDiagnosticSnapshot() {
        let all = AudioDevices.all()
        var lines: [String] = []
        lines.append("時間：\(Date())")
        lines.append("裝置總數：\(all.count)（輸出 \(outputDevices.count)、輸入 \(inputDevices.count)）")
        lines.append("預設輸出：\(defaultOutput?.name ?? "nil")")
        lines.append("預設輸入：\(defaultInput?.name ?? "nil")")
        lines.append("播放源群組：\(currentGroups.count)")
        lines.append("清單顯示：\(apps.count)（顯示系統程序：\(showsSystemProcesses)）")
        lines.append("播放狀態監聽：\(playbackObserver?.installedCount ?? 0) / \(watchedPlaybackIDs.count) 個行程")
        lines.append("")
        lines.append("— 所有裝置 —")
        for device in all {
            lines.append("  \(device.name)  out\(device.outputChannels) in\(device.inputChannels)  \(device.uid)")
        }
        lines.append("")
        lines.append("— 播放源 —")
        for group in currentGroups {
            lines.append("  \(group.name)  行程\(group.processes.count)  "
                + "\(group.isPlaying ? "播放中" : "閒置")\(group.isSystemProcess ? "／系統" : "")")
        }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SoundRouter-status.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// 讓實際跑著的引擎與目前設定一致。
    private func reconcile() {
        var groupsByKey: [String: AudioProcessGroup] = [:]
        for group in currentGroups {
            groupsByKey[group.key] = group
        }

        // 收掉已經不需要的引擎。
        for key in engines.keys where !shouldRunEngine(key: key, group: groupsByKey[key]) {
            teardownEngine(forKey: key)
        }

        for (key, setting) in settings {
            guard let group = groupsByKey[key], shouldRunEngine(key: key, group: group) else { continue }
            guard let deviceUID = setting.outputDeviceUID ?? defaultOutput?.uid else { continue }

            // 一組裡的所有行程共用一條路由，helper 發出的聲音才抓得到。
            let processIDs = group.processObjectIDs
            let target = engineTargets[key]

            if let engine = engines[key], target?.deviceUID == deviceUID, target?.processIDs == processIDs {
                // 已在跑且目標沒變，只要同步即時參數即可。
                engine.volume = setting.volume
                engine.isMuted = setting.muted
                engine.balance = setting.balance
                continue
            }

            teardownEngine(forKey: key)

            let engine = RouteEngine(
                label: setting.displayName.isEmpty ? key : setting.displayName,
                processObjectIDs: processIDs,
                outputDeviceUID: deviceUID
            )
            engine.volume = setting.volume
            engine.isMuted = setting.muted
            engine.balance = setting.balance

            do {
                try engine.start()
                engines[key] = engine
                engineTargets[key] = (deviceUID, processIDs)
                engineErrors[key] = nil
            } catch {
                engineErrors[key] = "\(error)"
                lastError = "\(setting.displayName.isEmpty ? key : setting.displayName)：\(error)"
            }
        }
    }

    private func shouldRunEngine(key: String, group: AudioProcessGroup?) -> Bool {
        guard let setting = settings[key], !setting.isPassthrough else { return false }
        return group != nil
    }

    private func teardownEngine(forKey key: String) {
        engines[key]?.stop()
        engines.removeValue(forKey: key)
        engineTargets.removeValue(forKey: key)
    }

    private func rebuildSnapshot() {
        var seen = Set<String>()
        var result: [RoutedApp] = []

        for group in currentGroups {
            // 系統守護程序只在使用者主動要求時列出，但已經設定過的一律顯示，
            // 否則使用者會找不到自己設過的東西。
            let setting = settings[group.key]
            let hasSettings = setting.map { !$0.isPassthrough } ?? false
            guard showsSystemProcesses || !group.isSystemProcess || hasSettings else { continue }

            seen.insert(group.key)
            result.append(RoutedApp(
                key: group.key,
                group: group,
                settings: setting ?? RouteSettings(displayName: group.name),
                isActive: engines[group.key]?.isRunning ?? false,
                error: engineErrors[group.key]
            ))
        }

        // 有記住設定但目前沒在跑的 App，列在後面。
        for (key, setting) in settings where !seen.contains(key) && !setting.isPassthrough {
            result.append(RoutedApp(
                key: key,
                group: nil,
                settings: setting,
                isActive: false,
                error: engineErrors[key]
            ))
        }

        apps = result
    }

    // MARK: - 持久化

    private static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SoundRouter", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("routes.json")
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: RouteSettings].self, from: data)
        else { return }
        settings = decoded
    }

    private func saveSettings() {
        // 已回到預設值的項目不必留在檔案裡。
        let persisted = settings.filter { !$0.value.isPassthrough }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(persisted) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
