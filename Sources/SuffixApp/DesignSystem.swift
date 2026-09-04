import SwiftUI
import ConvertKit

/// Deliberately thin.
///
/// An earlier version of this file invented a palette and a type scale. That
/// was the mistake: a Mac utility should look like the system, not like a brand.
/// The accent is whatever the user chose in System Settings, the type comes from
/// the system text styles, and surfaces use system materials — so the app
/// inherits every future macOS change for free.
enum Style {
    /// The user's own accent colour, not one we picked.
    static let accent = Color.accentColor
    /// The selection blue from DESIGN.md — used behind a destination
    /// extension and nowhere else, so it always means "this is the new thing".
    static let selection = Color(light: Color(red: 0.043, green: 0.384, blue: 0.965),
                                 dark:  Color(red: 0.239, green: 0.545, blue: 1.0))
    static let noticeCorner: CGFloat = 10
    static let noticeWidth: CGFloat = 348
}

extension Color {
    /// A colour that resolves per theme without an asset catalogue — this app
    /// is built by SwiftPM, which has nowhere to put one.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

/// `photo.png → photo.` + a highlighted `pdf`
///
/// The destination extension sits in a selection block, exactly as a
/// highlighted filename does in Finder. That block is the app's one emphasis
/// device — see DESIGN.md — so it appears here and nowhere decorative.
struct RenameChip: View {
    let from: String
    let to: String
    var font: Font = .caption

    /// Split a filename so the extension can be highlighted on its own.
    private var parts: (stem: String, ext: String) {
        guard let dot = to.lastIndex(of: ".") else { return (to, "") }
        return (String(to[to.startIndex..<dot]), String(to[dot...]))
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(from)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
            HStack(spacing: 0) {
                Text(parts.stem)
                Text(parts.ext)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Style.selection, in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .font(font.monospaced())
        .lineLimit(1)
        .truncationMode(.middle)
    }
}

/// A file's own thumbnail where one exists, its Finder icon otherwise.
enum Thumbnail {
    static func image(for url: URL) -> NSImage {
        if let img = NSImage(contentsOf: url), img.isValid, img.size.width > 0 {
            return img
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// The replace / keep-both choice.
///
/// A native radio group rather than the custom cards this used to be. The
/// resulting folder contents are shown underneath, because that difference is
/// far easier to see than to read.
struct OutputModePicker: View {
    @Binding var mode: OutputMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Wrapped in an HStack with a trailing Spacer: inside a grouped
            // Form, a Picker is laid out as a labelled row, which pushes the
            // radio buttons to the far right instead of beside their labels.
            HStack {
                Picker("", selection: $mode) {
                    ForEach(OutputMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Spacer()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(mode.explanation())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text("Afterwards:").foregroundStyle(.tertiary)
                    ForEach(mode == .replace ? ["photo.pdf"] : ["photo.png", "photo.pdf"],
                            id: \.self) { name in
                        Text(name)
                            .monospaced()
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            .font(.callout)
        }
    }
}
