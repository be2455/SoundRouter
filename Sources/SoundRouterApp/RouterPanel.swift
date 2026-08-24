import AudioRouterCore
import SwiftUI

struct RouterPanel: View {
    @EnvironmentObject private var manager: RouterManager
    @StateObject private var loginItem = LoginItem()

    var body: some View {
        VStack(spacing: 0) {
            SystemOutputSection()
            Divider()
            appList
            Divider()
            footer
        }
        // 寬度跟著內容走，但夾在上下限之間：App 名稱長度差異很大，
        // 完全放任會讓面板寬到荒謬；完全寫死則會在裝置多時把分段控制擠扁。
        .frame(minWidth: 380, idealWidth: 420, maxWidth: 560)
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
                // 每列約 68pt：名稱與音量兩行加上下 padding。
                FittingList(estimatedHeight: CGFloat(manager.apps.count) * 68) {
                    // 用 VStack 而非 LazyVStack：清單頂多幾十列，不需要延遲載入，
                    // 而且延遲建立的子視圖會讓視窗算不出正確高度。
                    VStack(spacing: 0) {
                        ForEach(manager.apps) { app in
                            AppRow(app: app)
                            if app.id != manager.apps.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 已註冊但使用者還沒在系統設定裡允許——不是錯誤，但也還沒生效。
            if loginItem.state == .requiresApproval {
                Button(L("loginItem.needsApproval")) { loginItem.openLoginItemsSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            // 只有真的有訊息時才佔一行，平常 footer 就是單純一排。
            if let error = manager.lastError ?? loginItem.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(manager.lastError != nil ? .red : .orange)
                    .lineLimit(2)
                    .help(error)
            }

            controlRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { loginItem.refresh() }
    }

    private var controlRow: some View {
        // 明確指定間距，不吃系統預設值——那個值在不同 macOS 版本可能不一樣。
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { loginItem.state.isOn },
                set: { _ in loginItem.toggle() }
            )) {
                Text(L("loginItem.launchAtLogin"))
                    .font(.caption)
            }
            .toggleStyle(.checkbox)

            Spacer()
            Button {
                manager.showsSystemProcesses.toggle()
            } label: {
                Image(systemName: manager.showsSystemProcesses ? "ellipsis.circle.fill" : "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(manager.showsSystemProcesses ? Color.accentColor : Color.secondary)
            .help(L("systemProcesses.toggleHelp"))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(L("app.quit"))
        }
    }
}

// MARK: - 系統輸出

private struct SystemOutputSection: View {
    @EnvironmentObject private var manager: RouterManager

    var body: some View {
        // 尺寸與字體都對齊下面每一列的 App：同樣是「一個播放目標加一組輸出選擇」，
        // 視覺上就該是同一種東西，而不是一個樣式不同的標題列。
        HStack(spacing: 10) {
            // 用電腦而不是喇叭：這一列講的是「整台機器的輸出」。
            Image(systemName: "desktopcomputer")
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)

            Text(L("systemOutput.title"))
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            // 跟每個 App 那一列用同一種控制項。系統輸出一定有指定裝置，
            // 所以沒有「自動」那一段。
            Picker("", selection: Binding(
                get: { manager.defaultOutput?.uid },
                set: { uid in
                    guard let uid,
                          let device = manager.outputDevices.first(where: { $0.uid == uid })
                    else { return }
                    manager.setSystemDefaultOutput(device)
                }
            )) {
                ForEach(manager.outputDevices) { device in
                    Image(systemName: DeviceIcon.symbol(for: device))
                        .help(device.name)
                        .tag(String?.some(device.uid))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - 單一播放源

private struct AppRow: View {
    let app: RoutedApp
    @EnvironmentObject private var manager: RouterManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if app.isPlaying {
                        Circle().fill(.green).frame(width: 6, height: 6)
                            .help(L("row.playing"))
                    }
                    if app.processCount > 1 {
                        Text("\(app.processCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .help(String(format: L("row.helperProcesses"), app.processCount))
                    }
                    if !app.isRunning {
                        Text(L("row.notRunning"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if let error = app.error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .help(error)
                    } else if app.isOutputDeviceOffline {
                        // 選定的裝置暫時不在——設定留著，回來就恢復，所以不是錯誤。
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .help(L("device.offline"))
                    } else if app.isStarting {
                        // 建立引擎要跟 coreaudiod 溝通，可能要一會兒。
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                    // 分段控制：第一段是「自動」（跟隨系統），其餘每個輸出裝置一段。
                    // 只放圖示是因為裝置名稱動輒十來個字，四五個名稱擺不進這個寬度。
                    Picker("", selection: Binding(
                        get: { app.settings.outputDeviceUID },
                        set: { manager.setOutputDevice($0, forKey: app.key) }
                    )) {
                        Text(L("route.auto"))
                            .help(L("route.followSystem"))
                            .tag(String?.none)
                        ForEach(manager.outputDevices) { device in
                            Image(systemName: DeviceIcon.symbol(for: device))
                                .help(device.name)
                                .tag(String?.some(device.uid))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                VolumeControl(
                    value: app.settings.volume,
                    isMuted: app.settings.muted,
                    onChange: { manager.setVolume($0, forKey: app.key) },
                    onToggleMute: { manager.setMuted(!app.settings.muted, forKey: app.key) }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(app.isRunning ? (app.isPlaying ? 1 : 0.75) : 0.5)
        // 分段控制沒有地方擺這兩個動作，改用右鍵選單。
        .contextMenu {
            if !app.settings.isPassthrough {
                Button(L("route.reset")) { manager.reset(key: app.key) }
            }
            if !app.isRunning {
                Button(L("route.forget")) { manager.forget(key: app.key) }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = app.group?.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 24, height: 24)
                .foregroundStyle(.tertiary)
        }
    }
}
