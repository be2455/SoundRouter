import AudioRouterCore
import SwiftUI

/// 音訊裝置的圖示。
///
/// 依傳輸類型決定，不看名稱——名稱是使用者可以自訂的，而且翻譯後也對不上。
enum DeviceIcon {
    static func symbol(for device: AudioDevice) -> String {
        switch device.transportKind {
        case .builtIn:
            // 內建裝置同時有喇叭與麥克風，用聲音而不是「筆電」來區分方向。
            return device.canOutput ? "laptopcomputer" : "mic"
        case .usb:
            return "hifispeaker"
        case .hdmi, .displayPort:
            return "display"
        case .bluetooth:
            return "dot.radiowaves.right"
        case .airPlay:
            return "airplayaudio"
        case .virtual:
            return "waveform"
        case .aggregate:
            return "rectangle.3.group"
        case .thunderbolt, .pci, .fireWire:
            return "cable.connector"
        case .other:
            return "speaker.wave.2"
        }
    }
}
