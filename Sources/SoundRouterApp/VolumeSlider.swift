import SwiftUI

/// 音量滑桿，0…1。
///
/// 不帶 `step`：帶了就會畫出一整排刻度線，20 格密密麻麻沒有資訊量。
/// 外觀只換填色，軌道與滑鈕維持原生，鍵盤操作與焦點環才是系統的。
struct VolumeSlider: View {
    let value: Float
    /// 靜音時滑桿畫在 0、填色改灰；`value` 本身保留，取消靜音回到原本音量。
    /// 靜音中拖動時滑桿照常跟著走；要不要取消靜音由呼叫端決定。
    var dimmed = false
    let label: String
    let onChange: (Float) -> Void
    /// 放開滑鈕時呼叫。
    var onRelease: () -> Void = {}
    @State private var isEditing = false

    var body: some View {
        Slider(
            value: Binding(get: { dimmed && !isEditing ? 0 : value }, set: { onChange($0) }),
            in: 0...1,
            onEditingChanged: {
                isEditing = $0
                if !$0 { onRelease() }
            }
        )
        .controlSize(.small)
        .tint(dimmed ? Color.gray : Color.accentColor)
        .accessibilityLabel(label)
    }
}
