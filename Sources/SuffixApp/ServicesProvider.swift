import AppKit
import ConvertKit

/// Suffix's entries in Finder's right-click menu.
///
/// macOS Services are the native answer to "do something with these files":
/// they arrive with the selection already attached, appear where people
/// already look, and need no extension target, no new permission and no
/// keyboard shortcut to remember.
@MainActor
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    func register() {
        NSApp.servicesProvider = self
        // Tells macOS to re-read the Info.plist, so the menu entries appear
        // without a logout the first time the app runs.
        NSUpdateDynamicServices()
    }

    // MARK: - Services

    @objc func mergeIntoPDF(_ pasteboard: NSPasteboard,
                            userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let files = Self.files(from: pasteboard)
        guard files.count >= 1 else { return }

        let directory = files[0].deletingLastPathComponent()
        let destination = uniqueDestination(in: directory,
                                            stem: PDFMerge.suggestedName(for: files),
                                            ext: "pdf")
        Task.detached(priority: .userInitiated) {
            do {
                try PDFMerge.merge(files, to: destination)
                Log.write("merged \(files.count) files -> \(destination.lastPathComponent)")
                await MainActor.run {
                    NoticeCenter.shared.show(Notice(
                        title: "Merged \(files.count) files",
                        detail: destination.lastPathComponent,
                        thumbnail: Thumbnail.image(for: destination),
                        reveal: { NSWorkspace.shared.activateFileViewerSelecting([destination]) }))
                }
            } catch {
                Log.write("merge FAILED: \(error.localizedDescription)")
                await MainActor.run {
                    NoticeCenter.shared.show(Notice(title: "Couldn't merge",
                                                    detail: error.localizedDescription,
                                                    isError: true))
                }
            }
        }
    }

    @objc func compressFiles(_ pasteboard: NSPasteboard,
                             userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let files = Self.files(from: pasteboard)
        guard !files.isEmpty else { return }

        CompressPanel.shared.show(files: files) { results in
            guard !results.isEmpty else { return }
            let saved = results.reduce(Int64(0)) { $0 + $1.saved }
            let percent = Self.percentSaved(results)
            Log.write("compressed \(results.count) files, saved \(saved) bytes")
            NoticeCenter.shared.show(Notice(
                title: results.count == 1 ? "Compressed" : "Compressed \(results.count) files",
                detail: "\(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)) smaller — \(percent)% saved",
                thumbnail: results.first.map { Thumbnail.image(for: $0.url) },
                reveal: { NSWorkspace.shared.activateFileViewerSelecting(results.map(\.url)) }))
        }
    }

    @objc func createZIP(_ pasteboard: NSPasteboard,
                         userData: String?,
                         error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let files = Self.files(from: pasteboard)
        guard !files.isEmpty else { return }

        let directory = files[0].deletingLastPathComponent()
        let stem = files.count == 1
            ? files[0].deletingPathExtension().lastPathComponent
            : directory.lastPathComponent
        let destination = uniqueDestination(in: directory, stem: stem, ext: "zip")

        Task.detached(priority: .userInitiated) {
            do {
                try Archiver.zip(files, to: destination)
                await MainActor.run {
                    NoticeCenter.shared.show(Notice(
                        title: "Archived \(files.count) item\(files.count == 1 ? "" : "s")",
                        detail: destination.lastPathComponent,
                        reveal: { NSWorkspace.shared.activateFileViewerSelecting([destination]) }))
                }
            } catch {
                await MainActor.run {
                    NoticeCenter.shared.show(Notice(title: "Couldn't create the archive",
                                                    detail: error.localizedDescription,
                                                    isError: true))
                }
            }
        }
    }

    // MARK: - Helpers

    /// The selected files, in the order Finder handed them over — which is the
    /// order the user can see on screen, and so the order a merge should use.
    private static func files(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls ?? []
    }

    private static func percentSaved(_ results: [CompressionResult]) -> Int {
        let before = results.reduce(Int64(0)) { $0 + $1.before }
        let after = results.reduce(Int64(0)) { $0 + $1.after }
        guard before > 0 else { return 0 }
        return Int((Double(before - after) / Double(before)) * 100)
    }
}
