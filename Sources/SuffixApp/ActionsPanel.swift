import SwiftUI
import AppKit
import ConvertKit

/// One window for everything you can do to a selection.
///
/// This replaced three separate entries buried in Finder's Services submenu.
/// Three loose items two levels deep were hard to find and gave no clue why one
/// of them was missing for a given selection; a single door that shows what
/// applies — and greys out what doesn't, with the reason — is easier to find
/// and honest about its limits.
@MainActor
final class ActionsPanel {
    static let shared = ActionsPanel()
    private var window: NSWindow?

    func show(files: [URL]) {
        guard !files.isEmpty else {
            NoticeCenter.shared.show(Notice(
                title: "Nothing selected",
                detail: "Pick some files in Finder first.",
                isError: true))
            return
        }

        window?.close()
        let view = ActionsView(files: files) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Suffix"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct ActionsView: View {
    let files: [URL]
    let dismiss: () -> Void

    /// Read once: detection opens every file, and the list doesn't change
    /// while the window is up.
    private var formats: [FileFormat?] {
        files.map(FileFormat.detect(at:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(files.count == 1 ? files[0].lastPathComponent : "\(files.count) files selected")
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text(summary)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(BatchOperation.allCases) { operation in
                    ActionRow(operation: operation,
                              problem: operation.accepts(formats) ? nil : operation.refusal) {
                        run(operation)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("or just rename a file's extension")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 380, height: 340)
    }

    private var summary: String {
        let names = Set(formats.compactMap { $0?.displayName }).sorted()
        let total = files.reduce(Int64(0)) { $0 + Compressor.size(of: $1) }
        let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return names.isEmpty ? size : "\(names.joined(separator: ", ")) · \(size)"
    }

    private func run(_ operation: BatchOperation) {
        dismiss()
        switch operation {
        case .mergePDF: BatchRunner.merge(files)
        case .compress: BatchRunner.compress(files)
        case .zip:      BatchRunner.zip(files)
        }
    }
}

private struct ActionRow: View {
    let operation: BatchOperation
    let problem: String?
    let run: () -> Void
    @State private var hovering = false

    private var icon: String {
        switch operation {
        case .mergePDF: return "doc.on.doc"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .zip:      return "doc.zipper"
        }
    }

    private var blurb: String {
        switch operation {
        case .mergePDF: return "One PDF, in the order you selected them"
        case .compress: return "Choose how much quality to trade"
        case .zip:      return "A single archive, nothing re-encoded"
        }
    }

    var body: some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .frame(width: 24)
                    .foregroundStyle(problem == nil ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(operation.title.replacingOccurrences(of: "…", with: ""))
                        .font(.body).fontWeight(.medium)
                    Text(problem ?? blurb)
                        .font(.caption)
                        .foregroundStyle(problem == nil ? .secondary : .tertiary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9).padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering && problem == nil ? Color.accentColor.opacity(0.12)
                                                     : Color.secondary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .disabled(problem != nil)
        .onHover { hovering = $0 }
    }
}

/// The work behind each action, shared by the panel, the shortcut and the
/// Services entry so all three behave identically.
@MainActor
enum BatchRunner {
    static func merge(_ files: [URL]) {
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

    static func compress(_ files: [URL]) {
        CompressPanel.shared.show(files: files) { results in
            guard !results.isEmpty else { return }
            let saved = results.reduce(Int64(0)) { $0 + $1.saved }
            let before = results.reduce(Int64(0)) { $0 + $1.before }
            let percent = before > 0 ? Int(Double(saved) / Double(before) * 100) : 0
            Log.write("compressed \(results.count) files, saved \(saved) bytes")
            NoticeCenter.shared.show(Notice(
                title: results.count == 1 ? "Compressed" : "Compressed \(results.count) files",
                detail: "\(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)) smaller — \(percent)% saved",
                thumbnail: results.first.map { Thumbnail.image(for: $0.url) },
                reveal: { NSWorkspace.shared.activateFileViewerSelecting(results.map(\.url)) }))
        }
    }

    static func zip(_ files: [URL]) {
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
}
