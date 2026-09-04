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
    /// Matches the corner radius macOS uses for notification banners.
    static let noticeCorner: CGFloat = 10
    static let noticeWidth: CGFloat = 344
}

/// `photo.png → photo.pdf`
///
/// Filenames are monospaced because that is what filenames are; the emphasis on
/// the destination is weight, not colour, so it reads the same under any accent.
struct RenameChip: View {
    let from: String
    let to: String
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 4) {
            Text(from)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
            Text(to)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
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
            Picker("", selection: $mode) {
                ForEach(OutputMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

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
