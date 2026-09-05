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
            // While a long conversion runs the mark fills from the baseline
            // up, so a video export is visibly working rather than apparently
            // hung. Otherwise: solid when active, ghosted when paused.
            Image(nsImage: MenuBarIcon.image(progress: model.progress,
                                             enabled: model.enabled))
        }

        Window("Suffix Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.rememberPosition()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)

        // Finder's right-click entries, for the things a rename cannot say.
        ServicesProvider.shared.register()

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
