import SwiftUI
import AppKit
import ConvertKit

/// What one notice says.
struct Notice: Identifiable {
    let id = UUID()
    var title: String
    var from: String?
    var to: String?
    var detail: String?
    var thumbnail: NSImage?
    var isError = false
    var undo: (() -> Void)?
    var reveal: (() -> Void)?
}

/// A notification banner.
///
/// This app cannot use Notification Center: an ad-hoc signature has no Team
/// Identifier, so macOS auto-denies authorization with "Notifications are not
/// allowed for this application" and never even prompts. A stable identity
/// costs $99/year.
///
/// So the banner is drawn here — but built from system parts (material, text
/// styles, the user's accent) and to the system's own proportions, so it reads
/// as part of macOS rather than as something invented.
struct NoticeView: View {
    let notice: Notice
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline).fontWeight(.semibold)

                if let from = notice.from, let to = notice.to {
                    RenameChip(from: from, to: to)
                }
                if let detail = notice.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if notice.undo != nil || notice.reveal != nil {
                    HStack(spacing: 8) {
                        if let undo = notice.undo {
                            Button("Undo") { undo(); dismiss() }
                        }
                        if let reveal = notice.reveal {
                            Button("Show") { reveal(); dismiss() }
                        }
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(12)
        .frame(width: Style.noticeWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Style.noticeCorner))
        .overlay(
            RoundedRectangle(cornerRadius: Style.noticeCorner)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        if let thumb = notice.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(notice.isError ? Color.red : Style.accent)
                .frame(width: 36, height: 36)
        }
    }
}

/// Presents notices where macOS puts its own: top-right, stacked, newest first.
@MainActor
final class NoticeCenter {
    static let shared = NoticeCenter()
    private var panels: [(panel: NSPanel, id: UUID)] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    private let spacing: CGFloat = 8
    private let margin: CGFloat = 12

    func show(_ notice: Notice, duration: TimeInterval = 5) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Style.noticeWidth, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false            // the view draws its own
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false

        let id = notice.id
        let host = NSHostingView(rootView: NoticeView(notice: notice) { [weak self] in
            self?.dismiss(id)
        })
        host.setFrameSize(host.fittingSize)
        panel.setContentSize(host.fittingSize)
        panel.contentView = host

        panels.append((panel, id))
        layout(animated: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.2
            $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        dismissTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    func dismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        guard let index = panels.firstIndex(where: { $0.id == id }) else { return }
        let panel = panels.remove(at: index).panel

        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
        layout(animated: true)
    }

    private func layout(animated: Bool) {
        guard let screen = NSScreen.main else { return }
        var y = screen.visibleFrame.maxY - margin

        for (panel, _) in panels {
            let height = panel.frame.height
            let origin = CGPoint(x: screen.visibleFrame.maxX - Style.noticeWidth - margin,
                                 y: y - height)
            if animated {
                NSAnimationContext.runAnimationGroup {
                    $0.duration = 0.16
                    panel.animator().setFrameOrigin(origin)
                }
            } else {
                panel.setFrameOrigin(origin)
            }
            y -= height + spacing
        }
    }
}

/// Blocking prompt for jobs big enough to be worth a second look.
@MainActor
enum Confirmation {
    static func ask(plan: ConversionPlan, file: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Convert \(file.lastPathComponent)?"
        alert.informativeText = """
            \(plan.summary)

            The pages arrive as a .zip next to the original, because there are \
            too many to sit loose in the folder.
            """
        alert.addButton(withTitle: "Convert")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
