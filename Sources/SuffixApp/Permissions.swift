import Foundation
import AppKit
import ConvertKit

/// What macOS is currently letting Suffix do, and how to ask for the rest.
///
/// There is no API that reports a TCC decision, so every state here is
/// measured by attempting the smallest possible version of the real thing:
/// reading one byte of a protected file, asking Finder a question that has no
/// side effect. Guessing from a stored flag would be worse than useless —
/// the whole failure mode of this app is looking fine while doing nothing.
enum Permission: String, CaseIterable, Identifiable {
    case fullDisk
    case finderAutomation
    case iWorkAutomation

    var id: String { rawValue }

    enum State: Equatable {
        case granted
        case denied
        case notAsked
        case notNeeded(String)      // e.g. no iWork app installed

        var isSatisfied: Bool {
            if case .granted = self { return true }
            if case .notNeeded = self { return true }
            return false
        }
    }

    // MARK: what it is

    var title: String {
        switch self {
        case .fullDisk:         return "Full Disk Access"
        case .finderAutomation: return "Control Finder"
        case .iWorkAutomation:  return "Control Pages, Keynote and Numbers"
        }
    }

    /// Required to do the main job, or only to do one extra thing.
    var isRequired: Bool { self == .fullDisk }

    var why: String {
        switch self {
        case .fullDisk:
            return """
            Renaming a file is something macOS reports to whoever is watching \
            the folder. Desktop, Documents, Downloads and iCloud Drive are \
            protected, so without this Suffix keeps running and silently does \
            nothing in the four folders you actually use.
            """
        case .finderAutomation:
            return """
            The keyboard shortcut arrives with no files attached, so Suffix has \
            to ask Finder what you have selected. Only needed for the shortcut — \
            the right-click menu hands over the selection by itself.
            """
        case .iWorkAutomation:
            return """
            A .pages or .key file is a sealed bundle that only Apple's own app \
            can open. Suffix asks Pages or Keynote to export it, in the \
            background, so the PDF is exactly the one they would have made.
            """
        }
    }

    /// The limit, stated in the same breath as the request. This is the part
    /// people are owed and rarely given.
    var limit: String {
        switch self {
        case .fullDisk:
            return """
            Suffix reads a file only when you rename it to a different format, \
            and only that file. It never opens a network connection — leave it \
            running and Activity Monitor's Network tab will read zero for as \
            long as you care to watch. The source is public if you would rather \
            check than take our word.
            """
        case .finderAutomation:
            return """
            One question, asked once per press: which files are selected. \
            Suffix cannot move, open or delete anything through this, and it \
            asks nothing when you are not pressing the shortcut.
            """
        case .iWorkAutomation:
            return """
            Suffix opens your document, exports a PDF, and closes it again — \
            it does not edit or save over the original. If the app was not \
            already running it is quit afterwards.
            """
        }
    }

    // MARK: where to grant it

    var settingsURL: URL? {
        switch self {
        case .fullDisk:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .finderAutomation, .iWorkAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }

    var settingsLabel: String {
        switch self {
        case .fullDisk:         return "Open Privacy & Security → Full Disk Access"
        default:                return "Open Privacy & Security → Automation"
        }
    }

    /// Automation is granted by a system prompt the first time it is needed,
    /// not by finding Suffix in a list it is not in yet.
    var isAskable: Bool { self != .fullDisk }

    // MARK: measuring it

    func measure() -> State {
        switch self {
        case .fullDisk:
            return Permission.canReadProtectedFile() ? .granted : .denied
        case .finderAutomation:
            return Permission.automationState(for: "com.apple.finder")
        case .iWorkAutomation:
            guard let installed = Permission.installediWorkApp() else {
                return .notNeeded("No Pages, Keynote or Numbers on this Mac")
            }
            return Permission.automationState(for: installed)
        }
    }

    /// Trigger the system prompt by doing the smallest real thing.
    func ask() {
        switch self {
        case .fullDisk:
            if let settingsURL { NSWorkspace.shared.open(settingsURL) }
        case .finderAutomation:
            _ = FinderSelection.canReadSelection
        case .iWorkAutomation:
            guard let bundleID = Permission.installediWorkApp(),
                  let desc = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc
            else { return }
            _ = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true)
        }
    }

    // MARK: - probes

    /// One byte out of a file only Full Disk Access can open.
    ///
    /// `isReadableFile(atPath:)` answers from the POSIX bits and says yes even
    /// when TCC will refuse, so the read has to actually happen.
    private static func canReadProtectedFile() -> Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    /// Asks TCC about an app without prompting and without sending anything.
    private static func automationState(for bundleID: String) -> State {
        guard let desc = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else {
            return .denied
        }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr:                             return .granted
        case OSStatus(errAEEventNotPermitted):  return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(procNotFound):            return .notAsked   // app isn't running yet
        default:                                return .notAsked
        }
    }

    private static func installediWorkApp() -> String? {
        ["com.apple.Pages", "com.apple.Keynote", "com.apple.Numbers",
         "com.apple.iWork.Pages", "com.apple.iWork.Keynote", "com.apple.iWork.Numbers"]
            .first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }
}

/// Live permission states, refreshed while a window that shows them is open.
///
/// macOS grants these in System Settings, in another process, with no
/// notification — so the only way for a checklist to be truthful is to keep
/// measuring it.
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published private(set) var states: [Permission: Permission.State] = [:]
    private var timer: Timer?

    init() { refresh() }

    func refresh() {
        var next: [Permission: Permission.State] = [:]
        for permission in Permission.allCases { next[permission] = permission.measure() }
        states = next
    }

    func startWatching() {
        stopWatching()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    var allRequiredGranted: Bool {
        Permission.allCases
            .filter(\.isRequired)
            .allSatisfy { states[$0]?.isSatisfied ?? false }
    }
}
