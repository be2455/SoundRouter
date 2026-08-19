import AudioToolbox
import CoreAudio
import Foundation

/// 打開一個輸入裝置並持續量測電平。
///
/// 主要用途是驗證虛擬訊源：混音端把音訊寫進「SoundRouter 訊源 N」的輸出，
/// 這個類別從同一個裝置的輸入端讀回來，證明 loopback 真的接通了。
/// 對一般使用者來說它也就是個輸入電平表。
public final class InputMonitor {
    private struct Levels {
        var left: Float32 = 0
        var right: Float32 = 0
        var ioProcCalls: Int64 = 0
    }

    public let deviceUID: String
    private var deviceID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private let levels: UnsafeMutablePointer<Levels>
    private let ioQueue: DispatchQueue

    public init(deviceUID: String) {
        self.deviceUID = deviceUID
        levels = UnsafeMutablePointer<Levels>.allocate(capacity: 1)
        levels.initialize(to: Levels())
        ioQueue = DispatchQueue(label: "com.soundrouter.monitor", qos: .userInitiated)
    }

    deinit {
        stop()
        levels.deinitialize(count: 1)
        levels.deallocate()
    }

    public var isRunning: Bool { ioProcID != nil }

    public var currentLevels: (left: Float, right: Float) {
        (Float(levels.pointee.left), Float(levels.pointee.right))
    }

    public var ioProcCalls: Int { Int(levels.pointee.ioProcCalls) }

    public func start() throws {
        guard !isRunning else { return }
        guard let id = AudioDevices.objectID(forUID: deviceUID) else {
            throw CoreAudioError(status: kAudioHardwareBadDeviceError, operation: "找不到裝置 \(deviceUID)")
        }
        deviceID = id

        let streams: [AudioObjectID] = try deviceID.readArray(
            kAudioDevicePropertyStreams,
            scope: kAudioObjectPropertyScopeInput,
            label: "讀取輸入 stream"
        )
        guard let first = streams.first else {
            throw CoreAudioError(
                status: kAudioHardwareUnsupportedOperationError,
                operation: "「\(deviceUID)」沒有輸入 stream"
            )
        }
        let format: AudioStreamBasicDescription = try first.read(
            kAudioStreamPropertyVirtualFormat, label: "讀取輸入格式"
        )
        guard format.isFloat32, format.mBytesPerFrame > 0 else {
            throw CoreAudioError(
                status: kAudioHardwareUnsupportedOperationError,
                operation: "只支援 32-bit float 輸入（實際為 \(format.debugSummary)）"
            )
        }

        let levels = self.levels
        let block: AudioDeviceIOBlock = { _, inputData, _, _, _ in
            levels.pointee.ioProcCalls += 1
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            guard list.count > 0 else { return }

            let channels = max(1, Int(format.mChannelsPerFrame))
            let nonInterleaved = format.isNonInterleaved
            let frames = Int(list[0].mDataByteSize) / Int(format.mBytesPerFrame)
            guard frames > 0 else { return }

            var peakLeft: Float32 = 0
            var peakRight: Float32 = 0

            for channel in 0..<min(2, channels) {
                let buffer = nonInterleaved ? list[min(channel, list.count - 1)] : list[0]
                guard let raw = buffer.mData else { continue }
                let samples = raw.assumingMemoryBound(to: Float32.self)
                let stride = nonInterleaved ? 1 : channels
                let start = nonInterleaved ? 0 : channel

                var peak: Float32 = 0
                for frame in 0..<frames {
                    let magnitude = abs(samples[start + frame * stride])
                    if magnitude > peak { peak = magnitude }
                }
                if channel == 0 { peakLeft = peak }
                if channel == 1 { peakRight = peak }
            }

            levels.pointee.left = peakLeft
            levels.pointee.right = channels == 1 ? peakLeft : peakRight
        }

        var procID: AudioDeviceIOProcID?
        try checked("建立監聽 IOProc") {
            AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, ioQueue, block)
        }
        ioProcID = procID
        try checked("啟動監聽") { AudioDeviceStart(deviceID, procID) }
    }

    public func stop() {
        if let ioProcID {
            AudioDeviceStop(deviceID, ioProcID)
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
            self.ioProcID = nil
        }
        deviceID = .unknown
    }
}
