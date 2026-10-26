import SwiftUI

/// 音量滑桿，0…1。
///
/// 不帶 `step`：帶了就會畫出一整排刻度線，20 格密密麻麻沒有資訊量。
/// 外觀只換填色，軌道與滑鈕維持原生，鍵盤操作與焦點環才是系統的。
struct VolumeSlider: View {
    let value: Float
    /// 靜音時滑桿畫在 0、填色改灰；`value` 本身保留，取消靜音回到原本音量。
    /// 靜音中拖動滑桿由呼叫端負責順便取消靜音。
    var dimmed = false
    let label: String
    let onChange: (Float) -> Void

    var body: some View {
        Slider(value: Binding(get: { dimmed ? 0 : value }, set: { onChange($0) }), in: 0...1)
            .controlSize(.small)
            .tint(dimmed ? Color.gray : Color.accentColor)
            .accessibilityLabel(label)
    }
}
