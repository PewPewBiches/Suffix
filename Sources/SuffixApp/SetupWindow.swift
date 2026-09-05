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

    /// `startStep` lets the menu jump straight to the permission checklist,
    /// which is where someone goes when the app has stopped working.
    func show(model: AppModel, startStep: Int = 0) {
        if let window {
            // Rebuild rather than reuse when a specific step was asked for:
            // the old view is still sitting on whichever step it was left on.
            if startStep != 0 {
                window.close()
                self.window = nil
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                return
            }
        }

        let view = OnboardingView(model: model, startStep: startStep,
                                  dismiss: { [weak self] in self?.close() }) { [weak self] in
            model.hasOnboarded = true
            self?.close()
        }

        // Borderless: setup draws its own System 7 window, frame and all.
        let window = S7WindowHost(size: NSSize(width: 560, height: 540))
        window.contentView = NSHostingView(rootView: view)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }
}
