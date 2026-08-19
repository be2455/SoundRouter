import SwiftUI

/// −／＋ 按鈕式的音量控制。
///
/// 刻意不用滑桿：這裡的數值範圍只有 0–100%，而選單列面板的列很窄，
/// 滑桿在這個寬度下很難精準拖到想要的值。按鈕每次固定走一格，結果可預期。
struct VolumeStepper: View {
    let value: Float
    /// 傳 nil 表示這個控制項沒有靜音功能（例如混音的主音量）。
    var isMuted: Bool?
    let onChange: (Float) -> Void
    var onToggleMute: (() -> Void)?

    /// 每格 5%，與 macOS 音量鍵的granularity 相近。
    private static let step: Float = 0.05

    /// 對齊到格線，避免反覆加減之後累積出 0.9999999 這種值。
    private static func snapped(_ raw: Float) -> Float {
        let clamped = max(0, min(1, raw))
        return (clamped / step).rounded() * step
    }

    private var percent: Int { Int((value * 100).rounded()) }

    var body: some View {
        HStack(spacing: 6) {
            if let isMuted, let onToggleMute {
                Button(action: onToggleMute) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .frame(width: 14)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isMuted ? Color.red : Color.secondary)
            }

            Button {
                onChange(Self.snapped(value - Self.step))
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(value <= 0)

            Text("\(percent)%")
                .font(.callout.monospacedDigit())
                .frame(width: 44)

            Button {
                onChange(Self.snapped(value + Self.step))
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(value >= 1)
        }
    }
}
