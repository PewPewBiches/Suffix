import SwiftUI
import AppKit

@main
struct SuffixApp: App {
    // Shared so the app delegate can reach the same model the scenes use.
    @StateObject private var model = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            // Filled while active, outline while paused, so the state reads at
            // a glance without opening the menu.
            Image(systemName: model.enabled
                  ? "arrow.triangle.2.circlepath.circle.fill"
                  : "arrow.triangle.2.circlepath.circle")
        }

        Window("Suffix Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)

        if NotificationProbe.runIfRequested() { return }

        if DesignPreview.runIfRequested() {
            NSApp.terminate(nil)
            return
        }

        if !UserDefaults.standard.bool(forKey: "hasOnboarded") {
            Task { @MainActor in
                SetupWindow.shared.show(model: AppModel.shared)
            }
        }
    }
}
