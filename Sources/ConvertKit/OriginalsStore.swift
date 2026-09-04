import Foundation

/// Keeps a copy of every file before it is converted, so a conversion the user
/// didn't mean can be undone. Entries expire on their own; without that this
/// quietly becomes a second copy of the user's photo library.
public enum OriginalsStore {
    // Settings, adjustable at launch. `nonisolated(unsafe)` because these are
    // configured once at startup and only read thereafter.
    nonisolated(unsafe) public static var root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Rename/Originals", isDirectory: true)
    }()

    /// How long a stashed original is kept before `prune()` removes it.
    nonisolated(unsafe) public static var retention: TimeInterval = 7 * 24 * 60 * 60

    /// Copy `url` aside. The stashed name keeps the *true* format's extension,
    /// so the backup is openable even though the user had renamed it.
    @discardableResult
    public static func stash(_ url: URL) throws -> URL {
        let fm = FileManager.default
        let day = dayStamp(Date())
        let dir = root.appendingPathComponent(day, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let trueExt = FileFormat.detect(at: url)?.preferredExtension ?? url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var dest = dir.appendingPathComponent("\(stem).\(trueExt)")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(stem) \(n).\(trueExt)")
            n += 1
        }
        try fm.copyItem(at: url, to: dest)
        return dest
    }

    /// Put a stashed original back, replacing whatever the conversion produced.
    public static func restore(_ backup: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: backup, to: destination)
    }

    /// Delete stashed originals older than `retention`.
    public static func prune(now: Date = Date()) {
        let fm = FileManager.default
        guard let days = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for day in days {
            guard let date = dayDate(fromStamp: day.lastPathComponent) else { continue }
            if now.timeIntervalSince(date) > retention {
                try? fm.removeItem(at: day)
            }
        }
    }

    /// Total bytes currently held, for display in settings.
    public static func size() -> Int64 {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// Day-granularity folder names, without a shared formatter (which Swift 6
/// concurrency checking rightly refuses to allow as global mutable state).
private let dayFields: Set<Calendar.Component> = [.year, .month, .day]

func dayStamp(_ date: Date) -> String {
    let c = Calendar(identifier: .gregorian).dateComponents(dayFields, from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

func dayDate(fromStamp stamp: String) -> Date? {
    let parts = stamp.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var c = DateComponents()
    (c.year, c.month, c.day) = (parts[0], parts[1], parts[2])
    return Calendar(identifier: .gregorian).date(from: c)
}
