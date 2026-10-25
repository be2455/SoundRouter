import AudioRouterCore
import SwiftUI

struct RouterPanel: View {
    @EnvironmentObject private var manager: RouterManager
    @StateObject private var loginItem = LoginItem()

    var body: some View {
        VStack(spacing: 0) {
            SystemOutputSection()
            Divider().padding(.horizontal, 16)
            appList
            ErrorBanner(loginError: loginItem.lastError)
            footer
        }
        .frame(width: 420)
        // 面板外用音量鍵調過的話，打開時重讀一次。
        .onAppear { manager.refresh() }
    }

    /// 由現有欄位算出分組，空的群組不顯示。`manager.apps` 本身已經排好序
    /// （播放中在前、一般 App 在系統程序前、名稱自然排序、未執行的在最後），
    /// 這裡只做 filter，群組內就沿用那個順序。
    private var groups: [(title: String, apps: [RoutedApp])] {
        let live = manager.apps.filter { !$0.settings.muted }
        return [
            (L("group.playing"), live.filter(\.isPlaying)),
            (L("group.other"), live.filter { !$0.isPlaying }),
            (L("group.muted"), manager.apps.filter(\.settings.muted)),
        ].filter { !$0.apps.isEmpty }
    }

    private var appList: some View {
        Group {
            if manager.apps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "speaker.slash")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(L("list.empty"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                let groups = groups
                // 每列 46pt，每個群組標題約 32pt，再加上下各 4pt 留白。
                FittingList(estimatedHeight: CGFloat(manager.apps.count) * 46 + CGFloat(groups.count) * 32 + 8) {
                    // 用 VStack 而非 LazyVStack：清單頂多幾十列，不需要延遲載入，
                    // 而且延遲建立的子視圖會讓視窗算不出正確高度。
                    VStack(spacing: 0) {
                        ForEach(groups, id: \.title) { group in
                            GroupHeader(title: group.title, count: group.apps.count)
                            ForEach(group.apps) { app in
                                AppRow(app: app)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private var footer: some View {
        // 明確指定間距，不吃系統預設值——那個值在不同 macOS 版本可能不一樣。
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { loginItem.state.isOn },
                set: { _ in loginItem.toggle() }
            )) {
                Text(L("loginItem.launchAtLogin"))
                    .font(.system(size: 12))
            }
            .toggleStyle(.checkbox)

            // 已註冊但使用者還沒在系統設定裡允許——不是錯誤，但也還沒生效。
            if loginItem.state == .requiresApproval {
                Button(L("loginItem.needsApproval")) { loginItem.openLoginItemsSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            Spacer()

            // 不是選單，是開關：只控制要不要列出系統程序。
            IconButton(
                systemImage: manager.showsSystemProcesses ? "ellipsis.circle.fill" : "ellipsis.circle",
                label: L("systemProcesses.show"),
                isOn: manager.showsSystemProcesses
            ) {
                manager.showsSystemProcesses.toggle()
            }
            .foregroundStyle(manager.showsSystemProcesses ? Color.accentColor : Color.secondary)
            .help(L("systemProcesses.toggleHelp"))

            IconButton(systemImage: "power", label: L("app.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .foregroundStyle(.secondary)
            .help(L("app.quit"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 48)
        .overlay(alignment: .top) { Divider() }
        .onAppear { loginItem.refresh() }
    }
}

// MARK: - 系統輸出

private struct SystemOutputSection: View {
    @EnvironmentObject private var manager: RouterManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: L("systemOutput.title"))
                .padding(.bottom, 8)

            // 原生 Menu：Esc、點外面關閉、方向鍵、VoiceOver 都由系統處理。
            // 系統輸出一定有指定裝置，所以沒有「跟隨系統輸出」那一項。
            Menu {
                ForEach(manager.outputDevices) { device in
                    DeviceMenuItem(
                        title: device.name,
                        subtitle: DeviceTransport.name(for: device),
                        isSelected: device.uid == manager.defaultOutput?.uid
                    ) {
                        manager.setSystemDefaultOutput(device)
                    }
                }
            } label: {
                outputButtonLabel
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            // 有些裝置（HDMI、部分 USB 介面）沒有硬體音量，那就不給滑桿。
            if let volume = manager.systemVolume {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 13))
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    VolumeSlider(value: volume, label: L("systemVolume.label")) {
                        manager.setSystemVolume($0)
                    }
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 13))
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    // 這裡一律顯示，即使是 100%。
                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.system(size: 12).monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var outputButtonLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.defaultOutput.map(DeviceIcon.symbol(for:)) ?? "speaker.wave.2")
                .font(.system(size: 16))
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.defaultOutput?.name ?? "—")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let device = manager.defaultOutput {
                    Text("\(DeviceTransport.name(for: device)) · \(L("systemOutput.current"))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 群組

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.44)
            .foregroundStyle(.secondary)
    }
}

private struct GroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            SectionTitle(text: title)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 單一播放源

private struct AppRow: View {
    let app: RoutedApp
    @EnvironmentObject private var manager: RouterManager
    @State private var isHovered = false

    private var isMuted: Bool { app.settings.muted }

    var body: some View {
        HStack(spacing: 10) {
            icon
                .opacity(isMuted ? 0.45 : 1)

            nameColumn

            VolumeSlider(
                value: app.settings.volume,
                dimmed: isMuted,
                label: String(format: L("row.volume"), app.name)
            ) {
                manager.setVolume($0, forKey: app.key)
            }

            valueText
                .frame(width: 32, alignment: .trailing)

            RouteMenu(app: app)

            IconButton(
                systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: String(format: L(isMuted ? "row.unmute" : "row.mute"), app.name),
                isOn: isMuted
            ) {
                manager.setMuted(!isMuted, forKey: app.key)
            }
            .foregroundStyle(isMuted ? Color.red : Color.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(
            isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .padding(.horizontal, 4)
        .onHover { isHovered = $0 }
        .contextMenu {
            if !app.settings.isPassthrough {
                Button(L("route.reset")) { manager.reset(key: app.key) }
            }
            if !app.isRunning {
                Button(L("route.forget")) { manager.forget(key: app.key) }
            }
        }
    }

    /// 固定寬度：空間不夠時名稱先省略，徽章與音量條保留。
    private var nameColumn: some View {
        HStack(spacing: 5) {
            Text(app.name)
                .font(.system(size: 13))
                .foregroundStyle(nameStyle)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(app.isRunning ? app.name : "\(app.name)（\(L("row.notRunning"))）")
            if app.processCount > 1 {
                Text("\(app.processCount)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize()
                    .help(String(format: L("row.helperProcesses"), app.processCount))
            }
            if app.isPlaying {
                PlayingBars()
                    .fixedSize()
            }
        }
        .frame(width: 104, alignment: .leading)
    }

    private var nameStyle: HierarchicalShapeStyle {
        if isMuted { return .tertiary }
        return app.isRunning ? .primary : .secondary
    }

    /// 100% 不顯示數字——那是預設值，沒有資訊量；靜音時改成紅字「靜音」。
    @ViewBuilder
    private var valueText: some View {
        if isMuted {
            Text(L("row.muted"))
                .font(.system(size: 11))
                .foregroundStyle(.red)
        } else if app.settings.volume < 1 {
            Text("\(Int((app.settings.volume * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = app.group?.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 18))
                .frame(width: 24, height: 24)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

/// 每列的輸出裝置選單。第一項是「跟隨系統輸出」（原本的「自動」），其後是所有輸出裝置。
private struct RouteMenu: View {
    let app: RoutedApp
    @EnvironmentObject private var manager: RouterManager

    private var selectedUID: String? { app.settings.outputDeviceUID }

    private var selectedName: String {
        guard let uid = selectedUID else { return L("route.auto") }
        return manager.outputDevices.first { $0.uid == uid }?.name ?? uid
    }

    var body: some View {
        Menu {
            Section(String(format: L("route.menuTitle"), app.name)) {
                DeviceMenuItem(
                    title: L("route.followSystem"),
                    subtitle: manager.defaultOutput?.name ?? "",
                    isSelected: selectedUID == nil
                ) {
                    manager.setOutputDevice(nil, forKey: app.key)
                }
                ForEach(manager.outputDevices) { device in
                    // 只在「這個 App」失敗過的裝置才停用：同一個裝置對別的 App 不一定會失敗。
                    let failed = device.uid == app.failedDeviceUID
                    DeviceMenuItem(
                        title: device.name,
                        subtitle: failed ? L("device.unavailable") : DeviceTransport.name(for: device),
                        isSelected: device.uid == selectedUID
                    ) {
                        manager.setOutputDevice(device.uid, forKey: app.key)
                    }
                    .disabled(failed)
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .foregroundStyle(selectedUID == nil ? Color.secondary : Color.accentColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selectedUID == nil ? Color.clear : Color.accentColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(String(format: L("route.buttonLabel"), app.name, selectedName))
        // 選定的裝置暫時不在——設定留著，回來就恢復，所以不是錯誤。
        .help(app.isOutputDeviceOffline ? L("device.offline") : selectedName)
    }
}

/// 選單裡的一個裝置。用 Toggle 是因為原生選單會把它畫成帶勾號的項目；
/// 第二個 Text 會變成選單項目的副標。
private struct DeviceMenuItem: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in action() })) {
            Text(title)
            Text(subtitle)
        }
    }
}

/// 「正在播放」的三根跳動音量條。不接真實電平：只有建了 tap 的 App 拿得到，
/// 混用會讓人以為其他 App 沒聲音。
private struct PlayingBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let delays: [Double] = [0, 0.2, 0.45]
    private static let period = 0.9

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(Self.delays, id: \.self) { delay in
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 3, height: reduceMotion ? 8 : height(at: time - delay))
                }
            }
            .frame(height: 12)
        }
        .foregroundStyle(Color.accentColor)
        .accessibilityElement()
        .accessibilityLabel(L("row.playing"))
    }

    /// 4…12pt 之間循環。
    private func height(at time: Double) -> CGFloat {
        8 + 4 * sin(2 * .pi * time / Self.period)
    }
}

// MARK: - 錯誤提示條

/// 只有有錯誤時才出現。主文講人話，原始訊息收在「詳細資訊」裡。
///
/// 失敗的單位是「某個 App → 某個裝置」，所以依目標裝置分組：
/// 一個裝置就說「X 無法使用」，多個就說「N 個裝置無法使用」。
private struct ErrorBanner: View {
    let loginError: String?
    @EnvironmentObject private var manager: RouterManager
    @State private var isExpanded = false

    private var failedApps: [RoutedApp] { manager.apps.filter { $0.error != nil } }

    private var failedDeviceNames: [String] {
        let uids = Set(failedApps.compactMap(\.failedDeviceUID))
        return uids.map { uid in manager.outputDevices.first { $0.uid == uid }?.name ?? uid }.sorted()
    }

    private var details: [String] {
        failedApps.map { "\($0.name)：\($0.error ?? "")" }
            + [manager.lastError, loginError].compactMap { $0 }
    }

    private var title: String {
        switch failedDeviceNames.count {
        case 0: return L("error.generic.title")
        case 1: return String(format: L("error.deviceUnavailable"), failedDeviceNames[0])
        default: return String(format: L("error.devicesUnavailable"), failedDeviceNames.count)
        }
    }

    private var summary: String {
        failedDeviceNames.isEmpty ? L("error.generic.summary") : L("error.route.summary")
    }

    var body: some View {
        if !details.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(L(isExpanded ? "error.hide" : "error.details")) {
                        isExpanded.toggle()
                    }
                    .controlSize(.small)
                }
                if isExpanded {
                    Text(details.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .lineSpacing(5)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.35)))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            // 面板關閉後回到預設的收合狀態。
            .onDisappear { isExpanded = false }
        }
    }
}

// MARK: - 共用

/// 28×28 的圖示按鈕。`isOn` 不為 nil 時是切換鈕，VoiceOver 會念出選取狀態。
private struct IconButton: View {
    let systemImage: String
    let label: String
    var isOn: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
    }
}
