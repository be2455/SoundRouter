import CoreAudio
import Foundation

/// 把 OSStatus 包成可讀的錯誤。Core Audio 的錯誤碼多半是 four-char code，
/// 直接印數字幾乎沒有可讀性，所以這裡一併還原成字串。
public struct CoreAudioError: LocalizedError, CustomStringConvertible {
    public let status: OSStatus
    public let operation: String

    public init(status: OSStatus, operation: String) {
        self.status = status
        self.operation = operation
    }

    public var errorDescription: String? { description }

    public var description: String {
        if let code = Self.fourCharCode(status) {
            return "\(operation) 失敗：'\(code)' (\(status))"
        }
        return "\(operation) 失敗：\(status)"
    }

    private static func fourCharCode(_ status: OSStatus) -> String? {
        let value = UInt32(bitPattern: status)
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }
}

/// 用來在執行期辨識 Optional 型別。
protocol _OptionalTypeMarker {}
extension Optional: _OptionalTypeMarker {}

@inline(__always)
func checked(_ operation: String, _ body: () -> OSStatus) throws {
    let status = body()
    guard status == noErr else {
        throw CoreAudioError(status: status, operation: operation)
    }
}

extension AudioObjectID {
    public static let system = AudioObjectID(kAudioObjectSystemObject)
    public static let unknown = AudioObjectID(kAudioObjectUnknown)

    public var isValid: Bool { self != .unknown }

    static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func isSettable(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var addr = Self.address(selector, scope, element)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(self, &addr, &settable) == noErr else { return false }
        return settable.boolValue
    }

    func hasProperty(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var addr = Self.address(selector, scope, element)
        return AudioObjectHasProperty(self, &addr)
    }

    /// 讀取固定大小的屬性值（AudioObjectID、UInt32、Float32、ASBD…）。
    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        as type: T.Type = T.self,
        label: String? = nil
    ) throws -> T {
        // `try? obj.read(sel)` 這種寫法會讓 T 有機會被推導成 Optional<實際型別>：
        // 兩種推導都能通過型別檢查（try? 會把巢狀 Optional 壓平），但 Optional 版本
        // 算出的大小多一個 tag byte，Core Audio 會回 kAudioHardwareBadPropertySizeError，
        // 然後 try? 又把錯誤吞掉變成 nil——整條路徑安靜地壞掉。
        // 呼叫端請一律明確寫 `as: X.self`；這裡擋住漏網的情況並講清楚原因。
        guard !(T.self is _OptionalTypeMarker.Type) else {
            // 呼叫端幾乎都是 `try?`，會把下面拋出的錯誤一起吞掉，
            // 所以 debug 版直接斷言，讓寫錯的呼叫點當場暴露。
            assertionFailure("讀取 \(selector.fourCharString) 時 T 被推導成 \(T.self)，請在呼叫端寫 as: 型別")
            throw CoreAudioError(
                status: kAudioHardwareIllegalOperationError,
                operation: "讀取屬性 \(selector.fourCharString) 時型別被推導成 \(T.self)，"
                    + "請在呼叫端明確指定 as: 型別"
            )
        }

        var addr = Self.address(selector, scope, element)
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        try checked(label ?? "讀取屬性 \(selector.fourCharString)") {
            AudioObjectGetPropertyData(self, &addr, 0, nil, &size, buffer)
        }
        return buffer.pointee
    }

    /// 讀取變動長度的屬性值（物件清單、stream 清單…）。
    func readArray<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        as type: T.Type = T.self,
        label: String? = nil
    ) throws -> [T] {
        var addr = Self.address(selector, scope, element)
        var size: UInt32 = 0
        try checked(label ?? "查詢屬性大小 \(selector.fourCharString)") {
            AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size)
        }
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }

        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { buffer.deallocate() }
        try checked(label ?? "讀取屬性 \(selector.fourCharString)") {
            AudioObjectGetPropertyData(self, &addr, 0, nil, &size, buffer)
        }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(size) / MemoryLayout<T>.stride))
    }

    func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        label: String? = nil
    ) throws -> String {
        var addr = Self.address(selector, scope, element)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil
        try checked(label ?? "讀取字串屬性 \(selector.fourCharString)") {
            withUnsafeMutablePointer(to: &value) { pointer in
                AudioObjectGetPropertyData(self, &addr, 0, nil, &size, pointer)
            }
        }
        return (value as String?) ?? ""
    }

    /// 讀取變動長度的 AudioBufferList（用來數 stream 的聲道數）。
    func readBufferListChannelCount(scope: AudioObjectPropertyScope) -> Int {
        var addr = Self.address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// 回傳某個 scope 下的 (AudioBuffer 個數, 總聲道數)。
    /// buffer 個數在計算 aggregate 裝置裡 tap 的 buffer 偏移量時會用到。
    func readBufferListCounts(scope: AudioObjectPropertyScope) -> (buffers: Int, channels: Int) {
        var addr = Self.address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size) == noErr, size > 0 else {
            return (0, 0)
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &addr, 0, nil, &size, raw) == noErr else { return (0, 0) }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return (list.count, list.reduce(0) { $0 + Int($1.mNumberChannels) })
    }

    func addListener(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        queue: DispatchQueue,
        handler: @escaping () -> Void
    ) -> AudioObjectPropertyListenerBlock? {
        var addr = Self.address(selector, scope, element)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(self, &addr, queue, block) == noErr else {
            return nil
        }
        return block
    }

    func removeListener(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        queue: DispatchQueue,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var addr = Self.address(selector, scope, element)
        AudioObjectRemovePropertyListenerBlock(self, &addr, queue, block)
    }
}

extension AudioObjectPropertySelector {
    /// AudioObjectPropertySelector 就是 UInt32 的 typealias，選擇子本身是 four-char code。
    var fourCharString: String {
        let bytes = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
