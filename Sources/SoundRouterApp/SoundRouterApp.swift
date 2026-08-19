import AudioRouterCore
import SwiftUI

@main
struct SoundRouterApp: App {
    @StateObject private var manager = RouterManager()

    var body: some Scene {
        MenuBarExtra {
            RouterPanel()
                .environmentObject(manager)
        } label: {
            Image(systemName: "slider.horizontal.below.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}
