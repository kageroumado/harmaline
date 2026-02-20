import SwiftUI

@main
struct HarmalineApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var manager = AppManager()

    var body: some Scene {
        Window("Harmaline", id: "main") {
            ContentView(manager: manager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 400)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
