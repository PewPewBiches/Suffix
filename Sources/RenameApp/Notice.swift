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

/// The card itself.
///
/// Built as a real view rather than the hand-assembled panel it replaces, so it
/// gets the system's own materials, type and focus behaviour — and can carry an
/// Undo button, which is the thing that makes an automatic conversion feel safe
/// rather than alarming.
struct NoticeView: View {
    let notice: Notice
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(notice.isError ? Color.red : Color.primary)

                if let from = notice.from, let to = notice.to {
                    RenameChip(from: from, to: to, size: 11.5)
                }
                if let detail = notice.detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if notice.undo != nil || notice.reveal != nil {
                    HStack(spacing: 14) {
                        if let undo = notice.undo {
                            Button("Undo") { undo(); dismiss() }
                                .buttonStyle(.plain)
                                .foregroundStyle(Style.accent)
                        }
                        if let reveal = notice.reveal {
                            Button("Show in Finder") { reveal(); dismiss() }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)

            // The close control appears on hover; at rest the card stays clean.
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(13)
        .frame(width: Style.noticeWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Style.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Style.corner)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        if let thumb = notice.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        } else {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(notice.isError ? Color.red : Style.accent)
                .frame(width: 38, height: 38)
        }
    }
}

/// Presents notices as floating panels under the menu bar.
///
/// The app cannot use Notification Center without a paid signing identity, so
/// this is the real notification surface rather than a fallback — which is why
/// it is built to the same standard as the rest of the UI.
@MainActor
final class NoticeCenter {
    static let shared = NoticeCenter()
    private var panels: [(panel: NSPanel, id: UUID)] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    private let spacing: CGFloat = 10
    private let margin: CGFloat = 14

    func show(_ notice: Notice, duration: TimeInterval = 5) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Style.noticeWidth, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false            // the SwiftUI card draws its own
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
            $0.duration = 0.22
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
            $0.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
        layout(animated: true)
    }

    /// Stack notices downward from under the menu bar, newest on top.
    private func layout(animated: Bool) {
        guard let screen = NSScreen.main else { return }
        var y = screen.visibleFrame.maxY - margin

        for (panel, _) in panels {
            let height = panel.frame.height
            let origin = CGPoint(x: screen.visibleFrame.maxX - Style.noticeWidth - margin,
                                 y: y - height)
            if animated {
                NSAnimationContext.runAnimationGroup {
                    $0.duration = 0.18
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
