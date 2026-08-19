import AudioRouterCore
import CoreAudio
import Foundation

// 刻意不引入 swift-argument-parser：這支 CLI 的參數很少，手刻可以讓整個
// 專案維持零外部相依，離線也建得起來。

let usage = """
audiorouter — 以 Core Audio process tap 做 per-app 音訊路由

用法：
  audiorouter devices                     列出所有音訊裝置
  audiorouter apps [--system] [--raw]     列出所有播放源（--system 含系統程序、--raw 不分組）
  audiorouter route <App> [選項]          把某個 App 的聲音導到指定裝置（前景執行，Ctrl-C 結束）
  audiorouter default-output <裝置>       切換系統預設輸出裝置
  audiorouter default-input <裝置>        切換系統預設輸入裝置
  audiorouter volume [0-1]                讀取／設定目前輸出裝置的音量
  audiorouter listen <裝置>               監看某個輸入裝置的電平

route 的選項：
  --to <裝置>        目標輸出裝置（名稱可模糊比對；省略時用系統目前的輸出）
  --volume <0-1>     音量倍率，1 為原音量（不提供增益放大）
  --balance <-1-1>   左右平衡
  --mute             靜音（等於把這個 App 消音，但仍佔用 tap）
  --keep-original    不靜音來源 App 的原輸出（診斷用：可在不打斷聆聽的情況下量測 tap）
  --debug            印出 tap 格式、buffer 佈局與 IOProc 呼叫統計
  --meter            持續顯示左右聲道電平，用來確認樣本真的有流過
  --seconds <n>      跑 n 秒後自動結束並還原（預設是一直跑到 Ctrl-C）

全域選項：
  --log <路徑>       把輸出寫到檔案（包在 .app 裡執行時沒有 stdout 可用）

<App> 與 <裝置> 都可以只給名稱的一部分，例如：
  audiorouter route music --to 外接喇叭 --volume 0.4
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("錯誤：" + message + "\n").utf8))
    exit(1)
}

func resolveDevice(_ query: String, in devices: [AudioDevice] = AudioDevices.outputs()) -> AudioDevice {
    if let exact = devices.first(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame })
        ?? devices.first(where: { $0.uid == query }) {
        return exact
    }
    let matches = devices.filter { $0.name.localizedCaseInsensitiveContains(query) }
    switch matches.count {
    case 0: fail("找不到輸出裝置「\(query)」。可用 `audiorouter devices` 查看清單。")
    case 1: return matches[0]
    default:
        fail("「\(query)」對應到多個裝置：\(matches.map(\.name).joined(separator: "、"))")
    }
}

func resolveProcesses(_ query: String) -> [AudioProcess] {
    // 用分組後的結果比對：搜到 helper 也會連同整個 App 的行程一起回傳。
    // 瀏覽器、Slack、LINE 的聲音都是 helper 送出的，只 tap 主行程會完全沒有聲音。
    let groups = AudioProcesses.searchGroups(query)
    guard !groups.isEmpty else {
        fail("找不到名稱含「\(query)」的播放源。可用 `audiorouter apps` 查看清單。")
    }
    if groups.count > 1 {
        // 完全同名的優先，否則要求使用者講清楚。
        if let exact = groups.first(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) {
            return exact.processes
        }
        fail("「\(query)」對應到多個播放源：\(groups.map(\.name).joined(separator: "、"))")
    }
    return groups[0].processes
}

func printDevices() {
    let devices = AudioDevices.all().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let defaultOutput = AudioDevices.defaultOutput()
    let defaultInput = AudioDevices.defaultInput()

    print("裝置：")
    for device in devices {
        var tags: [String] = [device.transport]
        if device.outputChannels > 0 { tags.append("out \(device.outputChannels)ch") }
        if device.inputChannels > 0 { tags.append("in \(device.inputChannels)ch") }
        var marks = ""
        if device.uid == defaultOutput?.uid { marks += " ←預設輸出" }
        if device.uid == defaultInput?.uid { marks += " ←預設輸入" }
        print("  \(device.name)  [\(tags.joined(separator: ", "))]\(marks)")
    }
}

func printApps(showRaw: Bool, showSystem: Bool) {
    if showRaw {
        // 未分組的原始行程清單，除錯用。
        let processes = AudioProcesses.all()
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        print("音訊行程（未分組，共 \(processes.count) 個）：")
        for process in processes {
            var tags: [String] = []
            if process.isPlaying { tags.append("播放中") }
            if process.isRecording { tags.append("錄音中") }
            let state = tags.isEmpty ? "閒置" : tags.joined(separator: "／")
            print("  \(process.name)  pid \(process.pid)  [\(state)]  \(process.bundleID ?? "")")
        }
        return
    }

    let groups = AudioProcesses.groups().filter { showSystem || !$0.isSystemProcess }
    guard !groups.isEmpty else {
        print("找不到任何播放源。")
        return
    }

    print("播放源（共 \(groups.count) 個）：")
    for group in groups {
        var tags: [String] = []
        if group.isPlaying { tags.append("播放中") }
        if group.isRecording { tags.append("錄音中") }
        if group.isSystemProcess { tags.append("系統") }
        let state = tags.isEmpty ? "閒置" : tags.joined(separator: "／")
        print("  \(group.name)  [\(state)]  \(group.bundleID ?? "")")
        // 一個 App 底下有多個發聲行程時列出來，路由會一起套用。
        if group.processes.count > 1 {
            for process in group.processes {
                print("      ↳ \(process.name)  pid \(process.pid)")
            }
        }
    }
}

// MARK: - 參數解析

var arguments = Array(CommandLine.arguments.dropFirst())

// 包在 .app 裡用 `open` 啟動時沒有終端機可以收輸出，所以支援把輸出導到檔案。
if let logIndex = arguments.firstIndex(of: "--log"), logIndex + 1 < arguments.count {
    let path = arguments[logIndex + 1]
    arguments.removeSubrange(logIndex...(logIndex + 1))
    freopen(path, "w", stdout)
    freopen(path, "a", stderr)
    setvbuf(stdout, nil, _IOLBF, 0)
}

guard let command = arguments.first else {
    print(usage)
    exit(0)
}
arguments.removeFirst()

func takeOption(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard index + 1 < arguments.count else { fail("\(name) 後面缺少值") }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

/// 可重複出現的選項（例如多個 --app）。
func takeAllOptions(_ name: String) -> [String] {
    var values: [String] = []
    while let value = takeOption(name) { values.append(value) }
    return values
}

func takeFlag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

switch command {
case "devices":
    printDevices()

case "apps":
    printApps(showRaw: takeFlag("--raw"), showSystem: takeFlag("--system"))

case "default-output", "default-input":
    guard let query = arguments.first else { fail("請指定裝置名稱") }
    let device = resolveDevice(query)
    do {
        if command == "default-output" {
            try AudioDevices.setDefaultOutput(device)
        } else {
            try AudioDevices.setDefaultInput(device)
        }
        print("已切換到「\(device.name)」")
    } catch {
        fail("\(error)")
    }

case "volume":
    guard let device = AudioDevices.defaultOutput() else { fail("找不到預設輸出裝置") }
    if let value = arguments.first {
        guard let volume = Float(value) else { fail("音量必須是 0 到 1 之間的數字") }
        do {
            try AudioDevices.setVolume(volume, on: device)
            print("「\(device.name)」音量設為 \(Int(volume * 100))%")
        } catch {
            fail("\(error)")
        }
    } else if let current = AudioDevices.volume(of: device) {
        print("「\(device.name)」目前音量 \(Int(current * 100))%")
    } else {
        print("「\(device.name)」不支援軟體音量控制")
    }

case "route":
    let mute = takeFlag("--mute")
    let showMeter = takeFlag("--meter")
    let showDebug = takeFlag("--debug")
    let keepOriginal = takeFlag("--keep-original")
    let secondsOption = takeOption("--seconds")
    let target = takeOption("--to")
    let volumeOption = takeOption("--volume")
    let balanceOption = takeOption("--balance")
    guard let appQuery = arguments.first else { fail("請指定要路由的 App") }

    let processes = resolveProcesses(appQuery)
    let device = target.map { resolveDevice($0) } ?? {
        guard let output = AudioDevices.defaultOutput() else { fail("找不到預設輸出裝置") }
        return output
    }()

    let engine = RouteEngine(
        label: processes[0].name,
        processObjectIDs: processes.map(\.id),
        outputDeviceUID: device.uid
    )
    if let volumeOption {
        guard let volume = Float(volumeOption) else { fail("--volume 必須是數字") }
        engine.volume = volume
    }
    if let balanceOption {
        guard let balance = Float(balanceOption) else { fail("--balance 必須是數字") }
        engine.balance = balance
    }
    engine.isMuted = mute
    if keepOriginal { engine.sourceBehavior = .keepOriginal }
    engine.diagnosticsEnabled = showDebug

    do {
        try engine.start()
    } catch {
        fail("""
        \(error)

        如果錯誤是 'priv'／權限相關，代表這個行程還沒取得音訊擷取授權。
        從終端機執行時，需要到「系統設定 → 隱私權與安全性 → 螢幕與系統音訊錄製」
        把終端機 App 勾選起來，再重新執行。
        """)
    }

    let names = processes.map(\.name).joined(separator: "、")
    print("「\(names)」已導向「\(device.name)」（音量 \(Int(engine.volume * 100))%\(engine.isMuted ? "，已靜音" : "")）")
    print("按 Ctrl-C 結束並還原。")

    // tap 與 aggregate 都掛在本行程上，離開就會消失，所以要留在前景。
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler {
        engine.stop()
        print("\n已還原路由。")
        exit(0)
    }
    source.resume()

    if let secondsOption {
        guard let seconds = Double(secondsOption) else { fail("--seconds 必須是數字") }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            engine.stop()
            print("已還原路由。")
            exit(0)
        }
    }

    var keepAlive: [Any] = []

    if showDebug {
        setvbuf(stdout, nil, _IOLBF, 0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        keepAlive.append(timer)
        timer.schedule(deadline: .now() + 1, repeating: .seconds(1))
        timer.setEventHandler {
            let d = engine.diagnostics
            print("""
            ── 診斷 ──────────────────────────
            tap 格式        \(d.tapFormat)
            輸出格式        \(d.outputFormat)
            input 偏移      \(d.inputBufferOffset)
            IOProc 呼叫次數 \(d.ioProcCalls)
            input buffers   \(d.inputBuffers)   frames \(d.inputFrames)
            output buffers  \(d.outputBuffers)   frames \(d.outputFrames)
            tap 原始峰值    \(String(format: "%.6f", d.rawInputPeak))
            提早返回代碼    \(d.bailReason)
            """)
        }
        timer.resume()
    }
    _ = keepAlive

    if showMeter {
        // 輸出導向檔案時 stdout 預設是全緩衝的，電平會卡在緩衝區裡。
        setvbuf(stdout, nil, _IOLBF, 0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler {
            let levels = engine.levels
            func bar(_ value: Float) -> String {
                let filled = Int((min(1, value) * 20).rounded())
                return String(repeating: "█", count: filled)
                    + String(repeating: "·", count: 20 - filled)
            }
            print("L \(bar(levels.left)) \(String(format: "%5.3f", levels.left))   "
                + "R \(bar(levels.right)) \(String(format: "%5.3f", levels.right))")
        }
        timer.resume()
        dispatchMain()
    }

    dispatchMain()

case "listen":
    let showMeter = takeFlag("--meter")
    let secondsOption = takeOption("--seconds")
    guard let deviceQuery = arguments.first else { fail("請指定要監看的裝置") }
    let device = resolveDevice(deviceQuery, in: AudioDevices.inputs())

    let monitor = InputMonitor(deviceUID: device.uid)
    do {
        try monitor.start()
    } catch {
        fail("\(error)")
    }
    print("正在監看「\(device.name)」的輸入電平。按 Ctrl-C 結束。")

    signal(SIGINT, SIG_IGN)
    let listenSignal = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    listenSignal.setEventHandler {
        monitor.stop()
        exit(0)
    }
    listenSignal.resume()

    var listenKeepAlive: [Any] = [listenSignal]

    if let secondsOption {
        guard let seconds = Double(secondsOption) else { fail("--seconds 必須是數字") }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            monitor.stop()
            print("監看結束。")
            exit(0)
        }
    }

    if showMeter {
        setvbuf(stdout, nil, _IOLBF, 0)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        listenKeepAlive.append(timer)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler {
            let levels = monitor.currentLevels
            func bar(_ value: Float) -> String {
                let filled = Int((min(1, value) * 20).rounded())
                return String(repeating: "█", count: filled) + String(repeating: "·", count: 20 - filled)
            }
            print("\(device.name)  L \(bar(levels.left)) \(String(format: "%5.3f", levels.left))   "
                + "R \(bar(levels.right)) \(String(format: "%5.3f", levels.right))   "
                + "IOProc \(monitor.ioProcCalls)")
        }
        timer.resume()
    }
    _ = listenKeepAlive
    dispatchMain()

case "-h", "--help", "help":
    print(usage)

default:
    fail("未知的指令「\(command)」\n\n\(usage)")
}
