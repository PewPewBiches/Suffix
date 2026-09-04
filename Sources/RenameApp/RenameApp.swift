import SwiftUI
import AppKit

@main
struct RenameApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            // Filled while active, outline while paused, so the state is
            // readable at a glance without opening the menu.
            Image(systemName: model.enabled
                  ? "arrow.triangle.2.circlepath.circle.fill"
                  : "arrow.triangle.2.circlepath.circle")
        }

        Window("Rename Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
        Notifier.requestPermission()
    }
}
