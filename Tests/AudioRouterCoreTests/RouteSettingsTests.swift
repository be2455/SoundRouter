import CoreAudio
import XCTest

@testable import AudioRouterCore

final class RouteSettingsTests: XCTestCase {

    /// isPassthrough 決定要不要建立 tap。判斷錯的話，要嘛白白攔截音訊，
    /// 要嘛使用者設定了卻沒生效，所以每個欄位都要能單獨打破它。
    func testIsPassthroughOnlyWhenEverythingIsDefault() {
        XCTAssertTrue(RouteSettings().isPassthrough)

        XCTAssertFalse(RouteSettings(outputDeviceUID: "SomeDevice").isPassthrough)
        XCTAssertFalse(RouteSettings(volume: 0.5).isPassthrough)
        XCTAssertFalse(RouteSettings(muted: true).isPassthrough)
        XCTAssertFalse(RouteSettings(balance: -0.3).isPassthrough)
    }

    /// 設定會被寫進 routes.json，欄位增減時要保證舊檔還讀得回來。
    func testCodableRoundTrip() throws {
        let original = RouteSettings(
            outputDeviceUID: "BuiltInSpeakerDevice",
            volume: 0.35,
            muted: true,
            balance: 0.5,
            displayName: "Spotify"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RouteSettings.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}

final class CoreAudioErrorTests: XCTestCase {

    /// Core Audio 的錯誤碼是 four-char code，直接印數字沒有可讀性。
    /// 這個轉換是除錯時唯一的線索，值得測。
    func testFourCharCodeIsRestoredInDescription() {
        // 'nope' = kAudioHardwareUnknownPropertyError 之類的可讀碼
        let status = OSStatus(bitPattern: 0x6E6F7065)  // "nope"
        let error = CoreAudioError(status: status, operation: "測試")

        XCTAssertTrue(error.description.contains("'nope'"), error.description)
        XCTAssertTrue(error.description.contains("測試"))
    }

    /// 不是可列印字元的錯誤碼要退回顯示數字，不能印出亂碼。
    func testNonPrintableStatusFallsBackToNumber() {
        let error = CoreAudioError(status: -50, operation: "測試")

        XCTAssertTrue(error.description.contains("-50"), error.description)
        XCTAssertFalse(error.description.contains("'"), error.description)
    }
}
