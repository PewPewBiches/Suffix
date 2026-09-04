import Foundation
import PDFKit
import AVFoundation

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
            pageCount: { PDFDocument(url: url)?.pageCount ?? 0 },
            mediaSeconds: {
                // Duration decides whether a media job is worth confirming.
                let asset = AVURLAsset(url: url)
                let seconds = CMTimeGetSeconds(asset.duration)
                return seconds.isFinite ? seconds : 0
            })

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
    ///
    /// The locking lives in small synchronous helpers because a lock must not
    /// be held across a suspension point, and media conversions suspend.
    @discardableResult
    public func perform(_ plan: ConversionPlan,
                        on url: URL,
                        progress: (@Sendable (Double) -> Void)? = nil) async throws -> ConversionResult {
        try claim(url.path)
        defer { release(url.path) }

        let originalName = url.lastPathComponent
        let result: ConversionResult
        switch plan {
        case .media, .documentToPDF, .pdfToText:
            result = try await performOutOfProcess(plan, on: url, progress: progress)
        default:
            result = try Converter(options: options).run(plan, on: url)
        }

        record(HistoryEntry(date: Date(),
                            finalURL: result.finalURL,
                            originalName: originalName,
                            summary: plan.summary,
                            backup: result.originalBackup))
        return result
    }

    private func claim(_ path: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard !inFlight.contains(path) else { throw ConversionError.alreadyRunning }
        inFlight.insert(path)
    }

    private func release(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        inFlight.remove(path)
    }

    private func record(_ entry: HistoryEntry) {
        lock.lock(); defer { lock.unlock() }
        _history.insert(entry, at: 0)
        if _history.count > 50 { _history.removeLast(_history.count - 50) }
    }

    /// Media and document conversions write to a temporary file first, then
    /// take the renamed file's place — so a long export that fails or is
    /// cancelled leaves the original untouched.
    private func performOutOfProcess(_ plan: ConversionPlan,
                                     on url: URL,
                                     progress: (@Sendable (Double) -> Void)?) async throws -> ConversionResult {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let target = FileFormat.forExtension(url.pathExtension)

        let backup = options.keepOriginal ? try OriginalsStore.stash(url) : nil
        var kept: URL?
        if options.outputMode == .keepBoth, let actual = FileFormat.detect(at: url) {
            let sibling = uniqueSibling(in: dir, stem: stem, ext: actual.preferredExtension)
            try fm.copyItem(at: url, to: sibling)
            kept = sibling
        }

        let scratch = fm.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(url.pathExtension)")
        defer { try? fm.removeItem(at: scratch) }

        switch plan {
        case .media(let from, let to, _):
            if SystemAudio.canWrite(to) {
                let staged = try MediaConverter.stage(url, as: from)
                defer { if staged != url { try? fm.removeItem(at: staged) } }
                try SystemAudio.convert(staged, to: to, destination: scratch)
            } else if to == .mp3 {
                let staged = try MediaConverter.stage(url, as: from)
                defer { if staged != url { try? fm.removeItem(at: staged) } }
                try await ExternalEncoder.encodeMP3(from: staged, to: scratch)
            } else {
                try await MediaConverter().run(url, from: from, to: to,
                                               destination: scratch, progress: progress)
            }
        case .documentToPDF(let from, _):
            try await MainActor.run {
                try DocumentConverter().toPDF(url, from: from, destination: scratch)
            }
        case .pdfToText:
            try await MainActor.run {
                try DocumentConverter().toText(url, destination: scratch)
            }
        default:
            throw ConversionError.encodingFailed(target ?? .pdf)
        }

        guard fm.fileExists(atPath: scratch.path) else {
            throw ConversionError.mediaExportFailed("no output was produced")
        }
        _ = try fm.replaceItemAt(url, withItemAt: scratch)
        return ConversionResult(finalURL: url, originalBackup: backup,
                                keptAlongside: kept, plan: plan)
    }

    private func uniqueSibling(in dir: URL, stem: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(stem).\(ext)")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
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
