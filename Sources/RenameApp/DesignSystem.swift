import SwiftUI
import ConvertKit

/// One visual language for the whole app.
///
/// Kept in a single place so the menu, the notices and the setup window can't
/// drift apart — a utility that lives in the menu bar is judged almost entirely
/// on whether its few surfaces feel like one thing.
enum Style {
    /// The "converted" colour. Used for the destination half of every
    /// filename, and nowhere decorative.
    static let accent = Color(light: Color(red: 0.055, green: 0.478, blue: 0.420),
                              dark:  Color(red: 0.310, green: 0.749, blue: 0.651))

    static let caution = Color(light: Color(red: 0.635, green: 0.376, blue: 0.102),
                               dark:  Color(red: 0.847, green: 0.627, blue: 0.361))

    static let corner: CGFloat = 12
    static let noticeWidth: CGFloat = 340
}

extension Color {
    /// A colour that resolves per theme without needing an asset catalogue —
    /// this app is built by SwiftPM, which has no place to put one.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

/// `photo.png → photo.pdf`
///
/// The app's central gesture, drawn the same way everywhere it appears. The
/// source is muted and the destination carries the accent, so the direction of
/// the change reads before any of the words do.
struct RenameChip: View {
    let from: String
    let to: String
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 5) {
            Text(from)
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: size - 2, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(to)
                .foregroundStyle(Style.accent)
                .fontWeight(.medium)
        }
        .font(.system(size: size, design: .monospaced))
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

/// A large, tappable choice — used for the replace/keep-both decision, where
/// a plain radio button would bury the difference that actually matters.
struct ChoiceCard<Detail: View>: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var detail: Detail

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: systemImage)
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? Style.accent : Color.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    detail
                }
                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Style.accent : Color.secondary.opacity(0.4))
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Style.accent.opacity(0.09) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Style.accent.opacity(0.55)
                                             : Color.secondary.opacity(0.18),
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
