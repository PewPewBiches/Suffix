import Foundation
import PDFKit

/// One completed conversion, kept so the user can see and undo it.
public struct HistoryEntry: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let finalURL: URL
    public let originalName: String
    public let summary: String
    public let backup: URL?

    public var canUndo: Bool {
        guard let backup else { return false }
        return FileManager.default.fileExists(atPath: backup.path)
    }
}

/// What the service decided to do about a renamed file.
public enum Decision: Sendable, CustomStringConvertible {
    case ignore
    case convert(ConversionPlan)
    /// Large or surprising jobs: ask before doing them.
    case confirm(ConversionPlan)

    public var description: String {
        switch self {
        case .ignore:          return "ignore"
        case .convert(let p):  return "convert(\(p.summary))"
        case .confirm(let p):  return "confirm(\(p.summary))"
        }
    }
}

/// Glue between "a file was renamed" and "the file was converted".
///
/// Deliberately UI-free so it can be driven by the menu-bar app or by tests.
public final class ConversionService: @unchecked Sendable {
    private let lock = NSLock()
    private var _history: [HistoryEntry] = []
    private var inFlight: Set<String> = []

    public var options: ConversionOptions
    /// Ask before converting jobs that produce many files.
    public var confirmLargeJobs = true

    public init(options: ConversionOptions = .init()) {
        self.options = options
    }

    public var history: [HistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        return _history
    }

    /// Work out what a renamed file deserves, without changing anything.
    public func decide(_ url: URL) -> Decision {
        let actual = FileFormat.detect(at: url)
        let result = ConversionPlan.make(
            source: actual,
            targetExtension: url.pathExtension,
            pageCount: { PDFDocument(url: url)?.pageCount ?? 0 })

        switch result {
        case .failure:
            return .ignore
        case .success(let plan):
            if confirmLargeJobs && plan.needsConfirmation { return .confirm(plan) }
            return .convert(plan)
        }
    }

    /// Run a plan, recording it in history. Safe to call concurrently; the same
    /// path will not be converted twice at once.
    @discardableResult
    public func perform(_ plan: ConversionPlan, on url: URL) throws -> ConversionResult {
        lock.lock()
        guard !inFlight.contains(url.path) else {
            lock.unlock()
            throw ConversionError.cannotRead(url)
        }
        inFlight.insert(url.path)
        lock.unlock()
        defer { lock.lock(); inFlight.remove(url.path); lock.unlock() }

        let originalName = url.lastPathComponent
        let result = try Converter(options: options).run(plan, on: url)

        lock.lock()
        _history.insert(HistoryEntry(date: Date(),
                                     finalURL: result.finalURL,
                                     originalName: originalName,
                                     summary: plan.summary,
                                     backup: result.originalBackup),
                        at: 0)
        if _history.count > 50 { _history.removeLast(_history.count - 50) }
        lock.unlock()
        return result
    }

    /// Put a converted file back the way it was.
    public func undo(_ entry: HistoryEntry) throws {
        guard let backup = entry.backup else { return }
        let destination = entry.finalURL
            .deletingLastPathComponent()
            .appendingPathComponent(entry.originalName)
        try OriginalsStore.restore(backup, to: destination)
        // The archive case leaves a .zip behind under a different name.
        if entry.finalURL.lastPathComponent != entry.originalName {
            try? FileManager.default.removeItem(at: entry.finalURL)
        }
        lock.lock()
        _history.removeAll { $0.id == entry.id }
        lock.unlock()
    }
}
