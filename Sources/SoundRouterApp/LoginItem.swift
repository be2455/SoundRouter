import Foundation
import ServiceManagement

/// 開機自動啟動的開關，包一層 `SMAppService`。
///
/// 兩個實務上會踩到的點：
///
///  - 註冊的是「這個 .app 目前所在的路徑」。之後把 App 搬到別的資料夾，
///    登入項目就會指向不存在的位置，必須重新註冊一次。
///  - 使用者可能在「系統設定 → 一般 → 登入項目」把它關掉，狀態會變成
///    `.requiresApproval`。這種情況不是錯誤，但也還沒真的生效，UI 要分開呈現。
@MainActor
final class LoginItem: ObservableObject {
    enum State {
        case enabled
        case disabled
        /// 已註冊，但使用者還沒在系統設定裡允許。
        case requiresApproval

        var isOn: Bool { self == .enabled }
    }

    @Published private(set) var state: State = .disabled
    @Published var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .requiresApproval
        default: state = .disabled
        }
    }

    func toggle() {
        do {
            if state.isOn || state == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            lastError = nil
        } catch {
            // ad-hoc 簽章、或 App 不在使用者能寫入的位置時都可能失敗。
            lastError = String(format: L("loginItem.failed"), error.localizedDescription)
        }
        refresh()
    }

    /// 帶使用者到系統設定的登入項目頁面，處理 requiresApproval 的情況。
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
