import Foundation
import UserNotifications

/// Diagnostic: can this build actually register with Notification Center?
/// Run with `--notify-test`. Exists because the answer decides whether the app
/// can use the system's notifications or must draw its own.
@MainActor
enum NotificationProbe {
    private static let logURL = URL(fileURLWithPath: "/tmp/suffix-notify-probe.txt")

    private static func log(_ line: String) {
        let existing = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        try? (existing + line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--notify-test") else { return false }
        try? FileManager.default.removeItem(at: logURL)
        let center = UNUserNotificationCenter.current()
        log("bundle id: \(Bundle.main.bundleIdentifier ?? "nil")")

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            log("requestAuthorization granted=\(granted) error=\(error?.localizedDescription ?? "none")")
            center.getNotificationSettings { settings in
                log("authorizationStatus: \(settings.authorizationStatus.rawValue) (2 == authorized)")
                let content = UNMutableNotificationContent()
                content.title = "Suffix"
                content.body = "invoice.png is now a PDF"
                center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                                 content: content, trigger: nil)) { err in
                    log("post error: \(err?.localizedDescription ?? "none")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
                }
            }
        }
        return true
    }
}
