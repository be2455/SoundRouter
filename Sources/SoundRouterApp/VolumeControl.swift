import SwiftUI

/// 音量滑軌，分成 20 格（每格 5%）。
///
/// 用 `Slider(value:in:step:)` 而不是自己算格數：帶 `step` 的滑軌會自動吸附到格線
/// 並畫出刻度，拖曳與方向鍵的行為也都是系統原生的。
struct VolumeControl: View {
    let value: Float
    /// 傳 nil 表示這個控制項沒有靜音功能。
    var isMuted: Bool?
    let onChange: (Float) -> Void
    var onToggleMute: (() -> Void)?

    /// 0…1 分成 20 格。
    private static let step: Float = 0.05

    private var percent: Int { Int((value * 100).rounded()) }

    var body: some View {
        HStack(spacing: 8) {
            if let isMuted, let onToggleMute {
                Button(action: onToggleMute) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .frame(width: 14)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isMuted ? Color.red : Color.secondary)
            }

            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: 0...1,
                step: Self.step
            )
            .controlSize(.small)

            Text("\(percent)%")
                .font(.callout.monospacedDigit())
                .foregroundStyle(isMuted == true ? .secondary : .primary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
