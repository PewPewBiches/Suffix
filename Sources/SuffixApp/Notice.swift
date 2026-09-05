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
        VStack(spacing: 0) {
            S7TitleBar(title: notice.isError ? "Suffix" : "Converted", close: dismiss)

            HStack(alignment: .top, spacing: 11) {
                icon

                VStack(alignment: .leading, spacing: 5) {
                    if let from = notice.from, let to = notice.to {
                        S7RenameChip(from: from, to: to, size: 12)
                    } else {
                        Text(notice.title)
                            .font(S7.chrome(12))
                            .foregroundStyle(S7.black)
                    }

                    if let detail = notice.detail {
                        Text(detail)
                            .font(S7.read(11.5))
                            .foregroundStyle(S7.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if notice.undo != nil || notice.reveal != nil {
                        HStack(spacing: 8) {
                            if let undo = notice.undo {
                                Button("Undo") { undo(); dismiss() }.buttonStyle(.s7)
                            }
                            if let reveal = notice.reveal {
                                Button("Show") { reveal(); dismiss() }.buttonStyle(.s7)
                            }
                        }
                        .padding(.top, 3)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(width: Style.noticeWidth, alignment: .leading)
            .background(S7.paper)
        }
        .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
        .background(Rectangle().fill(S7.shadow).offset(x: 2, y: 2))
        .onHover { hovering = $0 }
    }

    /// The file's own thumbnail if there is one; otherwise the System 7 alert
    /// figure — a bordered square carrying the six-colour mark for a success
    /// and an exclamation for a failure.
    @ViewBuilder private var icon: some View {
        if let thumb = notice.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipped()
                .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
        } else if notice.isError {
            Text("!")
                .font(S7.chrome(20))
                .foregroundStyle(S7.black)
                .frame(width: 34, height: 34)
                .background(S7.orange)
                .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
        } else {
            VStack(spacing: 0) {
                ForEach(S7.rainbow.indices, id: \.self) { i in
                    Rectangle().fill(S7.rainbow[i])
                }
            }
            .frame(width: 34, height: 34)
            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
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
            // The completion handler is nonisolated, and orderOut is main-actor
            // work; hopping explicitly is the difference between a warning today
            // and a crash under a stricter compiler.
            Task { @MainActor in panel.orderOut(nil) }
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
        alert.informativeText = "\(plan.summary)\n\n\(reason(for: plan))"
        alert.addButton(withTitle: "Convert")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Why this particular job is worth stopping for.
    private static func reason(for plan: ConversionPlan) -> String {
        switch plan {
        case .pdfToImageArchive:
            return """
                The pages arrive as a .zip next to the original, because there \
                are too many to sit loose in the folder.
                """
        case .media(_, _, let seconds):
            let minutes = max(1, Int((seconds / 60).rounded()))
            return """
                This is about \(minutes) minute\(minutes == 1 ? "" : "s") of video. \
                Converting it takes a while, and progress appears in the menu bar.
                """
        default:
            return "This one takes longer than most."
        }
    }
}
