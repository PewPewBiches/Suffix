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
            // While a long conversion runs the icon shows how far along it is,
            // so a video export is visibly working rather than apparently
            // hung. Otherwise: filled when active, outline when paused.
            if let fraction = model.progress {
                Image(systemName: progressSymbol(fraction))
            } else {
                Image(systemName: model.enabled
                      ? "arrow.triangle.2.circlepath.circle.fill"
                      : "arrow.triangle.2.circlepath.circle")
            }
        }

        Window("Suffix Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// SF Symbols ships pie-chart glyphs in quarters, which is as much precision as
/// a menu-bar icon can usefully carry.
private func progressSymbol(_ fraction: Double) -> String {
    switch fraction {
    case ..<0.25: return "circle.dotted"
    case ..<0.5:  return "circle.bottomhalf.filled"
    case ..<0.75: return "circle.righthalf.filled"
    default:      return "circle.fill"
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
