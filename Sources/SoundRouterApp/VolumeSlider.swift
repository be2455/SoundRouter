import SwiftUI

/// 音量滑桿，0…1。
///
/// 不帶 `step`：帶了就會畫出一整排刻度線，20 格密密麻麻沒有資訊量。
/// 外觀只換填色，軌道與滑鈕維持原生，鍵盤操作與焦點環才是系統的。
struct VolumeSlider: View {
    let value: Float
    /// 靜音時填色改灰，但值保留——取消靜音要回到原本的音量。
    var dimmed = false
    let label: String
    let onChange: (Float) -> Void

    var body: some View {
        Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0...1)
            .controlSize(.small)
            .tint(dimmed ? Color.gray : Color.accentColor)
            .accessibilityLabel(label)
    }
}
