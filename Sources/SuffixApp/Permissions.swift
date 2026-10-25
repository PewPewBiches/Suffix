import Foundation
import AppKit
import ConvertKit

/// What macOS is currently letting Suffix do, and how to ask for the rest.
///
/// There is no API that reports a TCC decision, so every state here is
/// measured by attempting the smallest possible version of the real thing.
/// Guessing from a stored flag would be worse than useless — the whole
/// failure mode of this app is looking fine while doing nothing.
///
/// **The order here is the order of the screen, and it matters.** This used to
/// lead with Full Disk Access, which cannot be granted from inside an app: it
/// means a trip to System Settings, a list the app is not in until it has been
/// refused once, and a + button. People got stuck there and never reached the
/// product. The three folders anyone actually renames files in are a one-click
/// system prompt each, and the Info.plist has always declared them.
enum Permission: String, CaseIterable, Identifiable {
    case folders
    case fullDisk
    case finderAutomation
    case iWorkAutomation

    var id: String { rawValue }

    enum State: Equatable {
        case granted
        case denied
        case notAsked
        case notNeeded(String)
        case partial(String)        // some folders yes, some no

        var isSatisfied: Bool {
            switch self {
            case .granted, .notNeeded: return true
            default: return false
            }
        }
    }

    // MARK: what it is

    var title: String {
        switch self {
        case .folders:          return "Desktop, Documents and Downloads"
        case .fullDisk:         return "Every other folder"
        case .finderAutomation: return "Control Finder"
        case .iWorkAutomation:  return "Control Pages, Keynote and Numbers"
        }
    }

    /// Only one thing is required, and it is the one macOS will just ask for.
    var isRequired: Bool { self == .folders }

    /// One sentence. The old version ran to four and nobody read any of them.
    var why: String {
        switch self {
        case .folders:
            return "The three folders you actually rename files in. macOS asks once per folder, and it is one click each."
        case .fullDisk:
            return "External drives, iCloud Drive, and anywhere outside your home folder. Only worth granting if you rename files out there."
        case .finderAutomation:
            return "Lets the keyboard shortcut ask Finder what you have selected. The right-click menu works without it."
        case .iWorkAutomation:
            return "Lets Suffix ask Pages or Keynote to export your document, so the PDF is exactly the one they would make."
        }
    }

    /// The limit, in the same breath as the request.
    var limit: String {
        switch self {
        case .folders:
            return "Suffix reads a file only when you rename it to a different format, and only that file. It has no networking in it."
        case .fullDisk:
            return "Same rule, wider area. Still no networking, still only the file you renamed."
        case .finderAutomation:
            return "One question per press: which files are selected. It cannot move, open or delete anything through this."
        case .iWorkAutomation:
            return "Opens the document, exports, closes. It does not edit or save over your original."
        }
    }

    /// What the button does, said plainly rather than named after a settings pane.
    var actionLabel: String {
        switch self {
        case .folders:          return "Ask macOS →"
        case .fullDisk:         return "Open Settings and show me the app"
        case .finderAutomation,
             .iWorkAutomation:  return "Ask macOS →"
        }
    }

    // MARK: measuring it

    /// The three folders, and whether each can be read right now.
    static let watched: [(name: String, url: URL)] = {
        let fm = FileManager.default
        return [("Desktop", FileManager.SearchPathDirectory.desktopDirectory),
                ("Documents", .documentDirectory),
                ("Downloads", .downloadsDirectory)]
            .compactMap { label, dir in
                fm.urls(for: dir, in: .userDomainMask).first.map { (label, $0) }
            }
    }()

    /// Not main-thread safe to call: a first attempt on a protected folder
    /// blocks until the person answers the system prompt.
    func measure() -> State {
        switch self {
        case .folders:
            let ok = Permission.watched.filter { Permission.canList($0.url) }.map(\.name)
            if ok.count == Permission.watched.count { return .granted }
            if ok.isEmpty { return .denied }
            return .partial(ok.joined(separator: " and ") + " only")
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

    func ask() {
        switch self {
        case .folders:
            // Touching each folder is what makes macOS show its own one-click
            // dialog. Off the main thread: each one blocks until answered.
            DispatchQueue.global(qos: .userInitiated).async {
                for folder in Permission.watched { _ = Permission.canList(folder.url) }
            }

        case .fullDisk:
            // Full Disk Access cannot be granted from in here. The app is not
            // in that list until macOS has refused it once, so opening the
            // pane alone strands people. Reveal the app too — it can be
            // dragged straight into the list.
            if let url = settingsURL { NSWorkspace.shared.open(url) }
            let app = Bundle.main.bundleURL
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NSWorkspace.shared.activateFileViewerSelecting([app])
            }

        case .finderAutomation, .iWorkAutomation:
            let target = self == .finderAutomation
                ? "com.apple.finder"
                : Permission.installediWorkApp()
            guard let target else { return }
            // Suffix has no Dock presence, so the consent dialog can open
            // behind whatever you were looking at. Come forward first.
            Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
            DispatchQueue.global(qos: .userInitiated).async {
                guard let desc = NSAppleEventDescriptor(bundleIdentifier: target).aeDesc else { return }
                _ = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true)
            }
        }
    }

    /// Steps only for the one permission a button cannot finish.
    var settingsSteps: [String]? {
        guard case .fullDisk = self else { return nil }
        return [
            "Two windows open: the settings list, and Suffix in Finder.",
            "Drag Suffix from the Finder window into the list.",
            "Switch it on.",
        ]
    }

    private var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    // MARK: - probes

    private static func canList(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// One byte out of a file only Full Disk Access can open. `isReadableFile`
    /// answers from the POSIX bits and says yes even when TCC will refuse, so
    /// the read has to actually happen.
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
/// Measuring happens on a background queue. A first read of a protected folder
/// blocks until the person answers the system prompt, and doing that on the
/// main thread would freeze the window behind the dialog.
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published private(set) var states: [Permission: Permission.State] = [:]
    private var timer: Timer?

    init() { refresh() }

    func refresh() {
        Task.detached(priority: .userInitiated) {
            var next: [Permission: Permission.State] = [:]
            for permission in Permission.allCases { next[permission] = permission.measure() }
            await MainActor.run { [next] in self.states = next }
        }
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
