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
    private let steps = ["Welcome", "How it works", "Permission", "Your choice"]

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
                case 1: HowItWorksStep()
                case 2: PermissionStep(model: model)
                default: ChoiceStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            Divider().opacity(0.5)
            controls
        }
        .frame(width: 520, height: 460)
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
            Button(step == steps.count - 1 ? "Start using Suffix" : "Continue") {
                if step == steps.count - 1 { finish() } else { withAnimation { step += 1 } }
            }
            .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 15)
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
                         ("square.grid.2x2", "Select several files and press ⌥⌘S to merge, compress or zip")],
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
    @ObservedObject var model: AppModel
    @State private var test: SelfTest.State = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Let Suffix reach your files")
                .font(.title2).fontWeight(.semibold)

            Text("""
                 macOS protects your Desktop, Documents and Downloads. Without \
                 access, Suffix keeps running but silently does nothing in \
                 exactly the folders you use most.
                 """)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            } label: {
                Label("Open Privacy & Security settings", systemImage: "arrow.up.forward.app")
            }

            Text("Turn on **Full Disk Access** for Suffix, then come back and test it.")
                .font(.callout)
                .foregroundStyle(.tertiary)

            Divider().opacity(0.4)

            Toggle("Skip Finder's extension warning", isOn: Binding(
                get: { !model.finderWarningShown },
                set: { model.finderWarningShown = !$0 }))
            Text("Otherwise Finder asks you to confirm every rename, before Suffix ever sees the file. Changing this restarts Finder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)

            // Proving it works is the whole point of this screen.
            HStack(spacing: 11) {
                Button("Test it now") {
                    test = .running
                    Task { test = await SelfTest.run() }
                }
                .disabled(test == .running)

                switch test {
                case .idle:
                    Text("Converts a sample file on your Desktop")
                        .font(.callout).foregroundStyle(.tertiary)
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
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
