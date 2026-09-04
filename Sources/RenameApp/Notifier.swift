import Foundation
import AppKit
import UserNotifications
import ConvertKit

/// User-facing notices. Main-actor bound because every path ends in UI.
///
/// Notifications need a signed bundle to register, which isn't guaranteed for a
/// locally-built app, so every path falls back to a lightweight on-screen
/// notice rather than failing silently.
@MainActor
enum Notifier {
    private static var useSystemNotifications = false

    static func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                Task { @MainActor in useSystemNotifications = granted }
            }
    }

    static func converted(name: String, summary: String, at url: URL) {
        post(title: "Converted", body: "\(name) — \(summary)")
    }

    static func failed(name: String, reason: String) {
        post(title: "Couldn't convert \(name)", body: reason)
    }

    private static func post(title: String, body: String) {
        if useSystemNotifications {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        } else {
            Toast.show(title: title, body: body)
        }
    }
}

/// A small floating notice, used when system notifications aren't available.
@MainActor
private final class Toast {
    private static var windows: [NSWindow] = []

    static func show(title: String, body: String) {
        let text = NSTextField(labelWithString: title)
        text.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(labelWithString: body)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [text, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.contentView = stack
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.addSubview(stack)
        panel.contentView = effect

        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.setContentSize(stack.fittingSize)
        if let screen = NSScreen.main {
            let f = panel.frame
            // Stack notices downward so several conversions stay readable.
            let offset = CGFloat(windows.count) * (f.height + 8)
            panel.setFrameOrigin(CGPoint(
                x: screen.visibleFrame.maxX - f.width - 20,
                y: screen.visibleFrame.maxY - f.height - 20 - offset))
        }
        panel.orderFrontRegardless()
        windows.append(panel)

        Task {
            try? await Task.sleep(for: .seconds(3))
            panel.animator().alphaValue = 0
            try? await Task.sleep(for: .milliseconds(300))
            panel.orderOut(nil)
            windows.removeAll { $0 === panel }
        }
    }
}

/// Blocking prompt for jobs big enough to be worth a second look.
@MainActor
enum Confirmation {
    static func ask(plan: ConversionPlan, file: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Convert \(file.lastPathComponent)?"
        alert.informativeText = """
            \(plan.summary)

            The pages are delivered as a .zip next to the original, \
            because there are too many to sit loose in the folder.
            """
        alert.addButton(withTitle: "Convert")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
