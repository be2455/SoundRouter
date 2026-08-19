import AppKit
import SwiftUI

/// 清單容器：塞得下就完全不用 `ScrollView`，塞不下才捲動。
///
/// 背景是 `MenuBarExtra` 的視窗依內容決定大小，而 `ScrollView` 沒有固有高度，
/// 在這個環境裡怎麼包都會出事：
///   - 只給 `maxHeight` → 被壓成 0，整塊清單消失；
///   - 只給 `minHeight` → 變成固定高度，清單被攔腰截斷；
///   - 用 GeometryReader 量內容高度再套用 → 在 MenuBarExtra 裡量到 0，同樣消失。
///
/// 所以這裡不量測，改用「估算列高 × 列數」判斷放不放得下。估算不準的代價很小
/// （頂多多留或少留一點空白），但不會再出現整塊消失或被切一半。
struct FittingList<Content: View>: View {
    private let estimatedHeight: CGFloat
    private let content: Content

    init(estimatedHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.estimatedHeight = estimatedHeight
        self.content = content()
    }

    /// 螢幕可用高度扣掉面板其餘部分（系統輸出區、分頁列、footer）的概略值。
    private var capHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        return max(240, screenHeight - 280)
    }

    var body: some View {
        if estimatedHeight <= capHeight {
            // 放得下就直接攤開，視窗自己長高，清單完整可見。
            content
        } else {
            ScrollView {
                content
            }
            .frame(height: capHeight)
        }
    }
}
