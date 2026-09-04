import Foundation
import os

/// A log a user can actually find.
///
/// This app fails silently by nature — a watcher that isn't running looks
/// exactly like a watcher with nothing to do — so the app records what it is
/// doing to `~/Library/Logs/Suffix.log`, and to the unified log for `log
/// stream`. Without this, diagnosing "it stopped working" is guesswork.
public enum Log {
    private static let logger = Logger(subsystem: "io.github.pewpewbiches.Suffix",
                                       category: "suffix")
    nonisolated(unsafe) public static var fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        return dir.appendingPathComponent("Suffix.log")
    }()

    private static let queue = DispatchQueue(label: "io.github.pewpewbiches.Suffix.log")

    public static func write(_ message: String) {
        logger.log("\(message, privacy: .public)")
        queue.async {
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(stamp)  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
