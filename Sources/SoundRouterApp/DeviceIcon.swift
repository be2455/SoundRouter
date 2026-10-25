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

/// 連接類型的顯示名稱。`AudioDevice.transport` 是給命令列看的固定中文，這裡才跟隨系統語言。
enum DeviceTransport {
    static func name(for device: AudioDevice) -> String {
        switch device.transportKind {
        case .builtIn: return L("transport.builtIn")
        case .usb: return "USB"
        case .hdmi: return "HDMI"
        case .displayPort: return "DisplayPort"
        case .bluetooth: return L("transport.bluetooth")
        case .airPlay: return "AirPlay"
        case .virtual: return L("transport.virtual")
        case .aggregate: return L("transport.aggregate")
        case .thunderbolt: return "Thunderbolt"
        case .pci: return "PCI"
        case .fireWire: return "FireWire"
        case .other: return L("transport.other")
        }
    }
}
