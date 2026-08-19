import AudioRouterCore
import SwiftUI

struct RouterPanel: View {
    @EnvironmentObject private var manager: RouterManager

    var body: some View {
        VStack(spacing: 0) {
            SystemOutputSection()
            Divider()
            appList
            Divider()
            footer
        }
        .frame(width: 400)
    }

    private var appList: some View {
        Group {
            if manager.apps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "speaker.slash")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("找不到任何播放源")
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
        HStack {
            if let error = manager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(error)
            }
            Spacer()
            Button {
                manager.showsSystemProcesses.toggle()
            } label: {
                Image(systemName: manager.showsSystemProcesses ? "gearshape.fill" : "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(manager.showsSystemProcesses ? Color.accentColor : Color.secondary)
            .help("顯示／隱藏系統程序（CoreSpeech、audiomxd 之類的背景服務）")

            Button("結束") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 系統輸出

private struct SystemOutputSection: View {
    @EnvironmentObject private var manager: RouterManager

    var body: some View {
        HStack(spacing: 8) {
            Text("系統輸出")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                ForEach(manager.outputDevices) { device in
                    Button {
                        manager.setSystemDefaultOutput(device)
                    } label: {
                        if device.uid == manager.defaultOutput?.uid {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                Text(manager.defaultOutput?.name ?? "（無）")
            }
            .controlSize(.small)
            .fixedSize()
        }
        .padding(12)
    }
}

// MARK: - 單一播放源

private struct AppRow: View {
    let app: RoutedApp
    @EnvironmentObject private var manager: RouterManager

    private var outputLabel: String {
        guard let uid = app.settings.outputDeviceUID else { return "跟隨系統" }
        return manager.outputDevices.first { $0.uid == uid }?.name ?? "（裝置已移除）"
    }

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
                            .help("正在播放")
                    }
                    if app.processCount > 1 {
                        Text("\(app.processCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .help("這個 App 有 \(app.processCount) 個發聲行程，會一起套用設定")
                    }
                    if !app.isRunning {
                        Text("未執行")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if app.error != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .help(app.error ?? "")
                    }
                    Menu {
                        Button {
                            manager.setOutputDevice(nil, forKey: app.key)
                        } label: {
                            if app.settings.outputDeviceUID == nil {
                                Label("跟隨系統", systemImage: "checkmark")
                            } else {
                                Text("跟隨系統")
                            }
                        }
                        Divider()
                        ForEach(manager.outputDevices) { device in
                            Button {
                                manager.setOutputDevice(device.uid, forKey: app.key)
                            } label: {
                                if device.uid == app.settings.outputDeviceUID {
                                    Label(device.name, systemImage: "checkmark")
                                } else {
                                    Text(device.name)
                                }
                            }
                        }
                        if !app.settings.isPassthrough {
                            Divider()
                            Button("重設這個 App") { manager.reset(key: app.key) }
                        }
                        if !app.isRunning {
                            Button("移除這筆設定") { manager.forget(key: app.key) }
                        }
                    } label: {
                        Text(outputLabel)
                    }
                    .controlSize(.small)
                    .fixedSize()
                }

                VolumeStepper(
                    value: app.settings.volume,
                    isMuted: app.settings.muted,
                    onChange: { manager.setVolume($0, forKey: app.key) },
                    onToggleMute: { manager.setMuted(!app.settings.muted, forKey: app.key) }
                )
                // 撐滿整列寬度，內部的靜音鈕／−／百分比／＋ 就會整組置中。
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(app.isRunning ? (app.isPlaying ? 1 : 0.75) : 0.5)
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
