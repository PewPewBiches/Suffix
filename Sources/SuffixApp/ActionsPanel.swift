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

        // Borderless: the panel draws its own System 7 title bar, so macOS
        // must not draw one above it.
        let window = S7WindowHost(size: NSSize(width: 412, height: 386))
        window.contentView = NSHostingView(rootView: view)
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
        ZStack {
            S7Desktop()
            S7Window(title: "File actions", close: dismiss) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(files.count == 1 ? files[0].lastPathComponent
                                              : "\(files.count) files selected")
                            .font(S7.data(13))
                            .foregroundStyle(S7.black)
                            .lineLimit(1).truncationMode(.middle)
                        Text(summary)
                            .font(S7.read(11.5))
                            .foregroundStyle(S7.dim)
                            .lineLimit(1).truncationMode(.middle)
                    }

                    S7Rule()

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
                            .font(S7.read(11))
                            .foregroundStyle(S7.faint)
                        Spacer()
                        Button("Close") { dismiss() }
                            .buttonStyle(.s7)
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(16)
                .frame(width: 380, height: 330, alignment: .topLeading)
            }
            .padding(14)
        }
        .frame(width: 412, height: 386)
        .background(S7.paper)
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

    /// A drawn mark rather than an SF Symbol — SF Symbols are the current
    /// system's voice, and this window is not speaking it.
    private var mark: some View {
        Group {
            switch operation {
            case .mergePDF:
                ZStack {
                    Rectangle().fill(S7.white).frame(width: 13, height: 16)
                        .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                        .offset(x: -3, y: -2)
                    Rectangle().fill(S7.white).frame(width: 13, height: 16)
                        .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                        .offset(x: 3, y: 2)
                }
            case .compress:
                VStack(spacing: 2) {
                    Text("▼").font(.system(size: 8))
                    Rectangle().fill(S7.black).frame(width: 16, height: 1.5)
                    Text("▲").font(.system(size: 8))
                }
                .foregroundStyle(S7.black)
            case .zip:
                Rectangle().fill(S7.white).frame(width: 15, height: 18)
                    .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                    .overlay(
                        VStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { _ in
                                Rectangle().fill(S7.black).frame(width: 4, height: 2)
                            }
                        }
                    )
            }
        }
        .frame(width: 26, height: 22)
        .opacity(problem == nil ? 1 : 0.35)
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
            HStack(spacing: 11) {
                mark
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.title.replacingOccurrences(of: "…", with: ""))
                        .font(S7.chrome(12))
                    Text(problem ?? blurb)
                        .font(S7.read(11.5))
                        .foregroundStyle(problem == nil
                                         ? (hovering ? S7.white : S7.dim)
                                         : S7.faint)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            // A row inverts under the pointer, the way a Finder row does.
            .foregroundStyle(hovering && problem == nil ? S7.white : S7.black)
            .padding(.vertical, 9).padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering && problem == nil ? S7.black : S7.white)
            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
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
