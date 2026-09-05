import SwiftUI
import AppKit
import ConvertKit

/// First-run setup, in the same world as the website.
///
/// Five steps, because each one is a thing the user must actually decide,
/// grant or see proved — not a marketing carousel. The permission step ends in
/// a real conversion, since this app's characteristic failure is looking
/// healthy while silently doing nothing.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var startStep: Int = 0
    let finish: () -> Void
    /// Closing the window without finishing. The window is borderless now, so
    /// without this there is no way out of setup except completing it.
    var dismiss: (() -> Void)?

    @State private var step: Int
    @StateObject private var permissions = PermissionMonitor()
    private let steps = ["Welcome", "How it works", "Permissions", "Test", "Your choice"]

    init(model: AppModel, startStep: Int = 0,
         dismiss: (() -> Void)? = nil, finish: @escaping () -> Void) {
        self.model = model
        self.startStep = startStep
        self.finish = finish
        self.dismiss = dismiss
        _step = State(initialValue: startStep)
    }

    var body: some View {
        ZStack {
            S7Desktop()
            S7Window(title: steps[step], close: dismiss) {
                VStack(spacing: 0) {
                    Group {
                        switch step {
                        case 0: WelcomeStep()
                        case 1: HowItWorksStep(model: model)
                        case 2: PermissionStep(permissions: permissions)
                        case 3: TestStep(model: model, permissions: permissions)
                        default: ChoiceStep(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    controls
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 540)
        .background(S7.paper)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            Rectangle().fill(S7.black).frame(height: 1)
            HStack(spacing: 12) {
                Text("Step \(step + 1) of \(steps.count)")
                    .font(S7.chrome(11))
                    .foregroundStyle(S7.dim)

                // The six-colour rule doubles as the progress bar: it fills in
                // one colour per step rather than being decoration.
                HStack(spacing: 0) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Rectangle()
                            .fill(i <= step ? S7.rainbow[i] : S7.faint.opacity(0.35))
                    }
                }
                .frame(width: 90, height: 4)
                .animation(.easeInOut(duration: 0.25), value: step)

                Spacer()

                if step > 0 {
                    Button("Back") { withAnimation(.easeInOut(duration: 0.16)) { step -= 1 } }
                        .buttonStyle(.s7)
                }
                Button(continueTitle) {
                    if step == steps.count - 1 { finish() }
                    else { withAnimation(.easeInOut(duration: 0.16)) { step += 1 } }
                }
                .buttonStyle(.s7Default)
                .keyboardShortcut(.defaultAction)

                if let dismiss {
                    Button("") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0).frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }

    /// On the permission step this is a deliberate "carry on without it"
    /// rather than a plain Continue — leaving it grants nothing, and
    /// pretending otherwise is how apps end up silently broken.
    private var continueTitle: String {
        if step == steps.count - 1 { return "Start using Suffix" }
        if step == 2 && !permissions.allRequiredGranted { return "Continue without it" }
        return "Continue"
    }
}

// MARK: - a shared page frame

/// Heading, six-colour rule, body. Every step is laid out this way, so they
/// read as pages of one document rather than five screens.
private struct Page<Content: View>: View {
    let title: String
    var lede: String?
    @ViewBuilder var content: Content

    @Environment(\.isRenderingPreview) private var isRendering

    var body: some View {
        // ImageRenderer draws a ScrollView as an empty box, so the preview
        // harness asks for the same content unwrapped.
        Wrapper(scrolls: !isRendering) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(S7.chrome(21))
                    .foregroundStyle(S7.black)
                S7Rule()
                if let lede {
                    Text(lede)
                        .font(S7.read(14))
                        .foregroundStyle(S7.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
    }

    private struct Wrapper<C: View>: View {
        let scrolls: Bool
        @ViewBuilder var content: C
        var body: some View {
            if scrolls { ScrollView { content } } else { content }
        }
    }
}

private struct RenderingPreviewKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var isRenderingPreview: Bool {
        get { self[RenderingPreviewKey.self] }
        set { self[RenderingPreviewKey.self] = newValue }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text("rename it.\nit converts.")
                    .font(S7.chrome(30))
                    .foregroundStyle(S7.black)
                    .lineSpacing(4)
                S7Rule(height: 4)
                Text("Change a file's extension in Finder and Suffix changes the file to match.")
                    .font(S7.read(15))
                    .foregroundStyle(S7.black)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No upload, no website, no app to open. Setup takes about a minute and ends by converting a real file in front of you.")
                    .font(S7.read(13))
                    .foregroundStyle(S7.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)
            Spacer()
        }
    }
}

private struct HowItWorksStep: View {
    @ObservedObject var model: AppModel
    @State private var stage = 0

    // A loop of the real gesture rather than a screenshot of it. Only the
    // middle step is a rename, so only it gets an arrow — showing
    // "invoice.png → invoice.png" for the others would say nothing.
    private let frames: [(String, String, String?)] = [
        ("Select a file", "invoice.png", nil),
        ("Press Return and edit the extension", "invoice.png", "invoice.pdf"),
        ("It converts, in place", "invoice.pdf", nil),
    ]

    var body: some View {
        Page(title: "three keystrokes") {
            VStack(alignment: .leading, spacing: 11) {
                ForEach(frames.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 11) {
                        Text("\(i + 1)")
                            .font(S7.chrome(11))
                            .foregroundStyle(i <= stage ? S7.white : S7.dim)
                            .frame(width: 18, height: 18)
                            .background(i <= stage ? S7.black : S7.white)
                            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(frames[i].0)
                                .font(S7.read(13))
                                .foregroundStyle(S7.black)
                            if let to = frames[i].2 {
                                S7RenameChip(from: frames[i].1, to: to)
                            } else {
                                Text(frames[i].1)
                                    .font(S7.data(12))
                                    .foregroundStyle(S7.dim)
                            }
                        }
                        .opacity(i <= stage ? 1 : 0.4)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: stage)

            S7Note(tag: "Also") {
                VStack(alignment: .leading, spacing: 6) {
                    Bullet("Images, PDFs, video, audio and documents")
                    Bullet("Rename a screenshot to .txt and get the words in it")
                    Bullet("Anything can be undone for seven days")
                    Bullet("Select several files and press \(model.shortcut.display) to merge, compress or zip")
                }
            }
        }
        .task {
            // Cycle the demo so the gesture is shown, not described.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1100))
                stage = (stage + 1) % 3
            }
        }
    }

    private struct Bullet: View {
        let text: String
        init(_ text: String) { self.text = text }
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(S7.black).frame(width: 4, height: 4).padding(.top, 6)
                Text(text)
                    .font(S7.read(12.5))
                    .foregroundStyle(S7.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PermissionStep: View {
    @ObservedObject var permissions: PermissionMonitor

    var body: some View {
        Page(title: "what Suffix needs",
             lede: "Three things, one of them required. Open a row for what each is for and — the part usually left out — what it does not allow.") {
            PermissionList(monitor: permissions, startExpanded: .fullDisk)
            PermissionAssurance()
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
        Page(title: "prove it works",
             lede: "This writes a small image to your Desktop, renames it, waits for Suffix to convert it, then deletes both. If anything in the chain is wrong you find out here rather than next week.") {

            HStack(spacing: 12) {
                Button(test == .passed ? "Run it again" : "Run the test") {
                    test = .running
                    Task { test = await SelfTest.run() }
                }
                .buttonStyle(.s7)
                .disabled(test == .running)

                switch test {
                case .idle:
                    EmptyView()
                case .running:
                    Text("Testing…").font(S7.read(13)).foregroundStyle(S7.dim)
                case .passed:
                    HStack(spacing: 6) {
                        Rectangle().fill(S7.green).frame(width: 9, height: 9)
                        Text("Working").font(S7.chrome(12)).foregroundStyle(S7.black)
                    }
                case .failed:
                    HStack(spacing: 6) {
                        Rectangle().fill(S7.red).frame(width: 9, height: 9)
                        Text("Did not convert").font(S7.chrome(12)).foregroundStyle(S7.black)
                    }
                }
            }

            if case .failed(let why) = test {
                S7Note(tag: "What happened") {
                    Text(why)
                        .font(S7.read(12.5))
                        .foregroundStyle(S7.black)
                        .fixedSize(horizontal: false, vertical: true)
                    if !permissions.allRequiredGranted {
                        Button("Open Full Disk Access") { Permission.fullDisk.ask() }
                            .buttonStyle(.s7)
                    }
                }
            }

            Rectangle().fill(S7.black).frame(height: 1).padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 7) {
                Toggle("Skip Finder's extension warning", isOn: Binding(
                    get: { !model.finderWarningShown },
                    set: { model.finderWarningShown = !$0 }))
                    .toggleStyle(S7CheckboxStyle())
                Text("Finder asks you to confirm every extension change, before Suffix ever sees the file. Turning this off restarts Finder, which takes a moment and loses nothing.")
                    .font(S7.read(12))
                    .foregroundStyle(S7.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ChoiceStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Page(title: "when a file converts…",
             lede: "Whichever you pick, you can change it later in Settings.") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(OutputMode.allCases) { option in
                    S7Radio(title: option.title,
                            isOn: model.outputMode == option) { model.outputMode = option }
                }
            }

            S7Note {
                Text(model.outputMode.explanation())
                    .font(S7.read(12.5))
                    .foregroundStyle(S7.black)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text("Afterwards:").font(S7.chrome(11)).foregroundStyle(S7.dim)
                    ForEach(model.outputMode == .replace ? ["photo.pdf"] : ["photo.png", "photo.pdf"],
                            id: \.self) { name in
                        Text(name)
                            .font(S7.data(12))
                            .foregroundStyle(S7.black)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                    }
                }
            }
        }
    }
}

/// System 7's radio button: a ring, filled when chosen.
struct S7Radio: View {
    let title: String
    let isOn: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(S7.white).frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(S7.black, lineWidth: 1))
                    if isOn { Circle().fill(S7.black).frame(width: 6, height: 6) }
                }
                Text(title).font(S7.read(13)).foregroundStyle(S7.black)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            return .failed("Can't write to your Desktop — grant Full Disk Access and try again")
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
        return .failed("The file was renamed but nothing converted. That is almost always Full Disk Access.")
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
