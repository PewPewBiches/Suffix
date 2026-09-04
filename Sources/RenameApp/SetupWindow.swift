import SwiftUI
import AppKit

/// The setup window, built as a real window rather than a SwiftUI `Window`
/// scene.
///
/// A menu-bar app has no main window, and a declared scene isn't instantiated
/// until something asks for it — so there is nothing for the app delegate to
/// show at first launch. Owning the window directly makes "open this on first
/// run" straightforward instead of a lifecycle puzzle.
@MainActor
final class SetupWindow {
    static let shared = SetupWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView(model: model) { [weak self] in
            model.hasOnboarded = true
            self?.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
