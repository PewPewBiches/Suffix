import SwiftUI
import AppKit
import ConvertKit

/// First-run setup.
///
/// Four steps, because each one is a thing the user must actually decide or
/// grant — not a marketing carousel. The permission step ends in a real
/// conversion, since this app's characteristic failure is looking healthy while
/// silently doing nothing.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var startStep: Int = 0
    let finish: () -> Void

    @State private var step: Int
    @StateObject private var permissions = PermissionMonitor()
    private let steps = ["Welcome", "How it works", "Permissions", "Test", "Your choice"]

    init(model: AppModel, startStep: Int = 0, finish: @escaping () -> Void) {
        self.model = model
        self.startStep = startStep
        self.finish = finish
        _step = State(initialValue: startStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider().opacity(0.5)

            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: HowItWorksStep(model: model)
                case 2: PermissionStep(permissions: permissions)
                case 3: TestStep(model: model, permissions: permissions)
                default: ChoiceStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            Divider().opacity(0.5)
            controls
        }
        .frame(width: 540, height: 520)
    }

    private var progress: some View {
        HStack(spacing: 7) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Style.accent : Color.secondary.opacity(0.22))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var controls: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // On the permission step the button is a deliberate "carry on
            // without it" rather than a plain Continue — leaving it grants
            // nothing, and pretending otherwise is how apps end up silently
            // broken.
            Button(continueTitle) {
                if step == steps.count - 1 { finish() } else { withAnimation { step += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 15)
    }

    private var continueTitle: String {
        if step == steps.count - 1 { return "Start using Suffix" }
        if step == 2 && !permissions.allRequiredGranted { return "Continue without it" }
        return "Continue"
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Style.accent)

            VStack(spacing: 9) {
                Text("Suffix")
                    .font(.largeTitle).fontWeight(.semibold)
                Text("Convert files by renaming them.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("No uploads, no websites, no app to open.\nIt works in every folder on your Mac.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
        }
        .padding(30)
    }
}

private struct HowItWorksStep: View {
    @ObservedObject var model: AppModel
    @State private var stage = 0

    // A loop of the real gesture, rather than a screenshot of it. Only the
    // middle step is a rename, so only it gets an arrow — showing
    // "invoice.png → invoice.png" for the others would say nothing.
    private let frames: [(String, String, String?)] = [
        ("Select a file", "invoice.png", nil),
        ("Press Return and edit the extension", "invoice.png", "invoice.pdf"),
        ("It converts, in place", "invoice.pdf", nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Three keystrokes")
                .font(.title2).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(frames.indices, id: \.self) { i in
                    HStack(spacing: 13) {
                        ZStack {
                            Circle()
                                .fill(i <= stage ? Style.accent : Color.secondary.opacity(0.2))
                                .frame(width: 22, height: 22)
                            Text("\(i + 1)")
                                .font(.caption).fontWeight(.bold)
                                .foregroundStyle(i <= stage ? .white : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(frames[i].0).font(.body).fontWeight(.medium)
                            Group {
                                if let to = frames[i].2 {
                                    RenameChip(from: frames[i].1, to: to)
                                } else {
                                    Text(frames[i].1)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .opacity(i <= stage ? 1 : 0.35)
                        }
                    }
                    .opacity(i <= stage ? 1 : 0.45)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: stage)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 8) {
                ForEach([("photo.on.rectangle.angled", "Images, PDFs, video, audio and documents"),
                         ("text.viewfinder", "Rename a screenshot to .txt to read the words in it"),
                         ("arrow.uturn.backward", "Anything can be undone for seven days"),
                         ("square.grid.2x2", "Select several files and press \(model.shortcut.display) to merge, compress or zip")],
                        id: \.1) { icon, text in
                    HStack(spacing: 9) {
                        // Fixed column so the labels line up rather than
                        // stepping in and out with each glyph's width.
                        Image(systemName: icon)
                            .frame(width: 17, alignment: .center)
                            .foregroundStyle(Style.accent)
                        Text(text)
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(30)
        .task {
            // Cycle the demo so the gesture is shown, not described.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1100))
                withAnimation { stage = (stage + 1) % 3 }
            }
        }
    }
}

private struct PermissionStep: View {
    @ObservedObject var permissions: PermissionMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("What Suffix needs from macOS")
                    .font(.title2).fontWeight(.semibold)

                Text("""
                     Three things, one of them required. Open a row to read what \
                     each one is for and — the part usually left out — what it \
                     does not allow.
                     """)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                PermissionList(monitor: permissions, startExpanded: .fullDisk)

                Divider().opacity(0.4)
                PermissionAssurance()
            }
            .padding(30)
        }
    }
}

/// Proving it works, which is the whole point of a setup screen for an app
/// whose characteristic failure is looking healthy while doing nothing.
private struct TestStep: View {
    @ObservedObject var model: AppModel
    @ObservedObject var permissions: PermissionMonitor
    @State private var test: SelfTest.State = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prove it works")
                .font(.title2).fontWeight(.semibold)

            Text("""
                 This writes a small image to your Desktop, renames it, waits for \
                 Suffix to convert it, and deletes both. If anything in the chain \
                 is wrong you will find out here rather than next week.
                 """)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 11) {
                Button(test == .passed ? "Run it again" : "Run the test") {
                    test = .running
                    Task { test = await SelfTest.run() }
                }
                .disabled(test == .running)

                switch test {
                case .idle:
                    EmptyView()
                case .running:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Testing…").font(.callout).foregroundStyle(.secondary)
                    }
                case .passed:
                    Label("Working", systemImage: "checkmark.circle.fill")
                        .font(.callout).fontWeight(.medium)
                        .foregroundStyle(Style.accent)
                case .failed(let why):
                    Label(why, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if case .failed = test, !permissions.allRequiredGranted {
                Button("Back to Full Disk Access") {
                    Permission.fullDisk.ask()
                }
                .font(.callout)
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Skip Finder's extension warning", isOn: Binding(
                    get: { !model.finderWarningShown },
                    set: { model.finderWarningShown = !$0 }))
                Text("""
                     Finder asks you to confirm every extension change, before \
                     Suffix ever sees the file. Turning this off restarts Finder, \
                     which takes a moment and loses nothing.
                     """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(30)
    }
}

private struct ChoiceStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("When a file converts…")
                .font(.title2).fontWeight(.semibold)
            Text("Whichever you pick, you can change it later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)

            OutputModePicker(mode: $model.outputMode)
                .padding(.top, 4)

            Spacer()
        }
        .padding(30)
    }

}

// MARK: - Self test

/// Creates a real file, renames it, and waits for the watcher to convert it.
///
/// This exercises the entire chain — permissions, events, conversion — which is
/// the only way to distinguish "set up correctly" from "silently broken".
enum SelfTest {
    enum State: Equatable {
        case idle, running, passed, failed(String)
    }

    static func run() async -> State {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let source = desktop.appendingPathComponent("Suffix test.png")
        let renamed = desktop.appendingPathComponent("Suffix test.pdf")

        // A small image drawn here rather than shipped as a resource.
        guard let data = sampleImage() else { return .failed("Could not build the sample") }
        do {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: renamed)
            try data.write(to: source)
        } catch {
            return .failed("Can't write to your Desktop — grant access above")
        }

        try? await Task.sleep(for: .milliseconds(400))
        do {
            try FileManager.default.moveItem(at: source, to: renamed)
        } catch {
            try? FileManager.default.removeItem(at: source)
            return .failed("Can't rename files on your Desktop")
        }

        // Give the watcher a moment to notice and convert.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            if FileFormat.detect(at: renamed) == .pdf {
                try? FileManager.default.removeItem(at: renamed)
                try? FileManager.default.removeItem(at: desktop.appendingPathComponent("Suffix test.png"))
                return .passed
            }
        }
        try? FileManager.default.removeItem(at: renamed)
        return .failed("Renamed, but nothing converted — check Full Disk Access")
    }

    private static func sampleImage() -> Data? {
        let size = 240
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(red: 0.055, green: 0.478, blue: 0.420, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: 70, y: 70, width: 100, height: 100))
        guard let image = ctx.makeImage() else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
