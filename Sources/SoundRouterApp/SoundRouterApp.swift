import AppKit
import AudioRouterCore
import SwiftUI

@main
struct SoundRouterApp: App {
    @NSApplicationDelegateAdaptor private var delegate: StatusMenuDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// 用 NSStatusItem + NSMenu 而不是 MenuBarExtra(.window)：
/// 全螢幕時只有系統選單的追蹤機制能讓選單列在滑鼠移開後仍保持顯示（控制中心也是這樣）。
@MainActor
final class StatusMenuDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = RouterManager()
    private let chooser = DeviceChooser()
    private var statusItem: NSStatusItem!
    private var hosting: SelfSizingHostingView<AnyView>!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hosting = SelfSizingHostingView(rootView: AnyView(RouterPanel().environmentObject(manager).environmentObject(chooser)))
        let item = NSMenuItem()
        item.view = hosting
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "slider.horizontal.below.rectangle", accessibilityDescription: "SoundRouter")
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        chooser.close()
        hosting.fit()
    }
}

/// 選單項目的視圖不會自己跟著內容長高；內容一變就重量一次大小。
final class SelfSizingHostingView<Content: View>: NSHostingView<Content> {
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.fit() }
    }

    func fit() {
        layoutSubtreeIfNeeded()
        let size = fittingSize
        if frame.size != size { setFrameSize(size) }
    }
}
