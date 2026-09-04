import Foundation
import AppKit

/// Finder's "Are you sure you want to change the extension?" dialog.
///
/// It appears before Suffix ever sees the file, so the app cannot suppress it
/// at conversion time — it is a Finder preference, and the only way past it is
/// to turn it off. For anyone using Suffix that dialog stands in front of the
/// one gesture the app exists for, which makes this worth offering directly
/// rather than leaving buried in Finder's settings.
@MainActor
enum FinderWarning {
    private static let key = "FXEnableExtensionChangeWarning" as CFString
    private static let domain = "com.apple.finder" as CFString

    /// macOS shows the warning unless the preference is explicitly false, so an
    /// absent value means "shown".
    static var isShown: Bool {
        guard let value = CFPreferencesCopyAppValue(key, domain) as? Bool else { return true }
        return value
    }

    /// Change the setting and restart Finder, which only reads it at launch.
    static func setShown(_ shown: Bool) {
        CFPreferencesSetAppValue(key, shown ? kCFBooleanTrue : kCFBooleanFalse, domain)
        CFPreferencesAppSynchronize(domain)
        restartFinder()
    }

    /// Finder relaunches itself immediately; no windows or work are lost.
    private static func restartFinder() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
    }
}
