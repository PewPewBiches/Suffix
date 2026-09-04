import Foundation
import AppKit
import ConvertKit

/// Whatever is selected in Finder right now.
///
/// A keyboard shortcut arrives with no files attached — unlike a Services menu
/// entry, which is handed the selection — so it has to go and ask. Finder will
/// only answer once the user has allowed Suffix to control it, which macOS
/// prompts for the first time this runs.
enum FinderSelection {
    /// The frontmost Finder window's selection, or an empty array.
    static func current() -> [URL] {
        let script = """
        tell application id "com.apple.finder"
            if (count of Finder windows) is 0 then return ""
            set chosen to selection
            set out to ""
            repeat with item_ in chosen
                set out to out & (POSIX path of (item_ as alias)) & linefeed
            end repeat
            return out
        end tell
        """
        guard let output = run(script) else { return [] }
        return output
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
    }

    /// True once Finder has answered at least once, meaning automation is
    /// allowed. Used to explain the shortcut doing nothing.
    static var canReadSelection: Bool {
        run("tell application id \"com.apple.finder\" to return \"ok\"") == "ok"
    }

    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let value = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.write("Finder selection unavailable: \(error[NSAppleScript.errorMessage] ?? "unknown")")
            return nil
        }
        return value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
