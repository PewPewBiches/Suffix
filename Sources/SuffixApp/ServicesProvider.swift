import AppKit
import ConvertKit

/// Suffix's entry in Finder's right-click menu.
///
/// One entry, not three. Services land two levels deep under Finder's
/// "Services" submenu, where three loose items were both hard to find and
/// silently incomplete — an entry simply vanished when macOS decided the
/// selection didn't match, with no way to know why. A single door opens the
/// actions panel, which shows every operation and greys out the ones that
/// don't apply along with the reason.
@MainActor
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    func register() {
        NSApp.servicesProvider = self
        // Makes macOS re-read the Info.plist, so the entry appears without a
        // logout the first time the app runs.
        NSUpdateDynamicServices()
    }

    @objc func showActions(_ pasteboard: NSPasteboard,
                           userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        ActionsPanel.shared.show(files: Self.files(from: pasteboard))
    }

    /// The selected files, in the order Finder handed them over — which is the
    /// order shown on screen, and so the order a merge should use.
    private static func files(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
