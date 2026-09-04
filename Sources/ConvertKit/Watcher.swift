import Foundation
import CoreServices

/// Watches the file system for files whose *name* changed, anywhere under the
/// given roots.
///
/// FSEvents is the right tool here rather than polling: it reports a specific
/// `ItemRenamed` flag, so we react to the exact gesture the app is built around
/// instead of rescanning folders and guessing.
public final class RenameWatcher {
    /// Directory trees never worth reacting to: system files, and churn we
    /// would only filter out later.
    ///
    /// These are applied in `isEligible` rather than through
    /// `FSEventStreamSetExclusionPaths`, which reports success but silently
    /// suppresses *every* event on a file-level stream.
    public static let excludedPrefixes = [
        "/System/", "/private/var/", "/usr/", "/bin/", "/sbin/", "/dev/",
        NSHomeDirectory() + "/Library/",
    ]

    /// Path fragments that disqualify an event wherever they appear.
    private static let excludedFragments = [
        "/.Trash/", "/node_modules/", "/.git/", "/Caches/",
        "/.build/", "/DerivedData/", "/.Spotlight-V100/", "/.fseventsd/",
    ]

    private let roots: [URL]
    private let queue = DispatchQueue(label: "com.rakshitchawla.Suffix.watcher", qos: .utility)
    private let handler: @Sendable (URL) -> Void
    private var stream: FSEventStreamRef?

    /// - Parameter handler: called with each renamed file. Runs off the main thread.
    public init(roots: [URL], handler: @escaping @Sendable (URL) -> Void) {
        // FSEvents reports canonical paths, so watch canonical paths too —
        // otherwise a root reached through a symlink (/tmp -> /private/tmp)
        // silently never matches anything.
        self.roots = roots.map { $0.resolvingSymlinksInPath() }
        self.handler = handler
    }

    deinit { stop() }

    public func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        // FileEvents gives per-file granularity (and the Renamed flag);
        // without it FSEvents only names the enclosing directory.
        // UseCFTypes is not optional: without it the callback receives a C
        // char** rather than a CFArray, and reading it as an array is wrong.
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents
                         | kFSEventStreamCreateFlagNoDefer
                         | kFSEventStreamCreateFlagIgnoreSelf
                         | kFSEventStreamCreateFlagUseCFTypes)

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let watcher = Unmanaged<RenameWatcher>.fromOpaque(info).takeUnretainedValue()
                let names = unsafeBitCast(paths, to: NSArray.self)
                for i in 0..<count {
                    guard let path = names[i] as? String else { continue }
                    if ProcessInfo.processInfo.environment["SUFFIX_DEBUG"] != nil {
                        FileHandle.standardError.write(
                            "raw event flags=0x\(String(flags[i], radix: 16)) \(path)\n".data(using: .utf8)!)
                    }
                    watcher.handle(path: path, flags: flags[i])
                }
            },
            &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,                       // coalesce bursts; a rename is one event
            flags)
        else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    /// Decide whether one FSEvents callback entry is a rename we care about.
    private func handle(path: String, flags: FSEventStreamEventFlags) {
        guard flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 else { return }
        guard flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 else { return }
        guard Self.isEligible(path: path) else { return }
        // A rename reports both the old and the new name, and FSEvents may
        // coalesce Removed into the same event as Renamed. Existence on disk
        // is the reliable test of which name survived — the Removed flag is
        // not, and filtering on it drops real renames.
        guard FileManager.default.fileExists(atPath: path) else { return }
        handler(URL(fileURLWithPath: path))
    }

    /// Cheap filters applied before touching the disk.
    static func isEligible(path: String) -> Bool {
        if excludedPrefixes.contains(where: path.hasPrefix) { return false }
        if excludedFragments.contains(where: path.contains) { return false }
        let name = (path as NSString).lastPathComponent
        if name.hasPrefix(".") { return false }
        // Only extensions we could actually convert to are worth a look.
        return FileFormat.forExtension((path as NSString).pathExtension) != nil
    }
}
