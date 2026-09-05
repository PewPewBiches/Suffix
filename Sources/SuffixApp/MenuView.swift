import SwiftUI
import ConvertKit

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Convert on rename", isOn: $model.enabled)
            .toggleStyle(.checkbox)

        if let fraction = model.progress {
            Text("Converting… \(Int(fraction * 100))%")
        }

        // Without Full Disk Access the app runs perfectly and converts nothing
        // in the folders anyone uses. Saying so here is the difference between
        // a five-minute fix and assuming the app is broken.
        if !Permission.fullDisk.measure().isSatisfied {
            Divider()
            Text("No access to your files — nothing will convert")
            Button("Fix this…") {
                SetupWindow.shared.show(model: model, startStep: 2)
            }
        }

        Divider()

        Button("File actions for Finder selection…") {
            ActionsPanel.shared.show(files: FinderSelection.current())
        }

        Divider()

        if model.history.isEmpty {
            Text("No conversions yet")
            Text("Rename a file's extension in Finder to convert it.")
        } else {
            Section("Recent") {
                ForEach(model.history.prefix(8)) { entry in
                    Menu("\(entry.originalName)  →  \(entry.finalURL.lastPathComponent)") {
                        Text(entry.summary)
                        Button("Show in Finder") { model.reveal(entry) }
                        if entry.canUndo {
                            Button("Undo — put \(entry.originalName) back") { model.undo(entry) }
                        }
                    }
                }
            }
        }

        if let error = model.lastError {
            Divider()
            Text(error)
        }

        Divider()

        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("How to use Suffix…") { SetupWindow.shared.show(model: model) }

        Button("Permissions…") { SetupWindow.shared.show(model: model, startStep: 2) }

        Button("Quit Suffix") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

/// Settings, in tabs.
///
/// This was one scrolling form of six sections covering renaming, Finder,
/// quality and storage at once. Tabs match how macOS settings windows are
/// built and, more usefully, let each pane be read on its own. The chrome is
/// the same System 7 vocabulary as setup and the website — see System7.swift.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab: Tab = .general
    @Environment(\.isRenderingPreview) private var isRendering

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", converting = "Converting", finder = "Finder"
        case permissions = "Permissions", undo = "Undo"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            S7Desktop()
            S7Window(title: "Suffix Settings") {
                VStack(spacing: 0) {
                    tabStrip
                    Rectangle().fill(S7.black).frame(height: 1)
                    PaneScroll(scrolls: !isRendering) {
                        Group {
                            switch tab {
                            case .general:     GeneralPane(model: model)
                            case .converting:  ConvertingPane(model: model)
                            case .finder:      ActionsPane(model: model)
                            case .permissions: PermissionsPane()
                            case .undo:        UndoPane(model: model)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // Top-aligned: a VStack shorter than its frame centres itself,
                // which put a grey band between the title bar and the tabs.
                .frame(height: 430, alignment: .top)
            }
            .padding(14)
        }
        .frame(width: 560, height: 500)
        .background(S7.paper)
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { item in
                Button { tab = item } label: {
                    Text(item.rawValue)
                        .font(S7.chrome(11))
                        .foregroundStyle(tab == item ? S7.white : S7.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(tab == item ? S7.black : S7.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if item != Tab.allCases.last {
                    Rectangle().fill(S7.black).frame(width: 1)
                }
            }
        }
        // Fixed, or the dividers grow to whatever height the window has spare.
        .frame(height: 26)
    }

    /// ImageRenderer draws a ScrollView as an empty box, so the preview
    /// harness asks for the same content unwrapped.
    private struct PaneScroll<C: View>: View {
        let scrolls: Bool
        @ViewBuilder var content: C
        var body: some View {
            if scrolls { ScrollView { content } } else { content }
        }
    }
}

// MARK: - pane furniture

/// A titled group of settings, with the explanation underneath rather than
/// in a tooltip nobody opens.
private struct Group7<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(S7.chrome(12))
                .foregroundStyle(S7.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(S7.black)

            content

            if let footer {
                Text(footer)
                    .font(S7.read(11.5))
                    .foregroundStyle(S7.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(S7.white)
        .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
    }
}

/// label on the left, value on the right, hairline between rows.
private struct Field7<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(S7.read(13)).foregroundStyle(S7.black)
            Spacer(minLength: 12)
            value
        }
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group7(title: "Watching",
                   footer: "Suffix only acts when a file's new extension is one it can produce and the contents don't already match.") {
                Toggle("Convert files when I rename them", isOn: $model.enabled)
                    .toggleStyle(S7CheckboxStyle())
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }))
                    .toggleStyle(S7CheckboxStyle())
                Toggle("Watch external drives too", isOn: $model.includeVolumes)
                    .toggleStyle(S7CheckboxStyle())

                Field7(label: "Status") {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(model.isWatching ? S7.green : S7.faint)
                            .frame(width: 9, height: 9)
                            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                        Text(model.isWatching ? "Watching your files" : "Paused")
                            .font(S7.chrome(11))
                            .foregroundStyle(S7.black)
                    }
                }
            }

            Group7(title: "When a file converts") {
                ForEach(OutputMode.allCases) { option in
                    S7Radio(title: option.title, isOn: model.outputMode == option) {
                        model.outputMode = option
                    }
                }
                Text(model.outputMode.explanation())
                    .font(S7.read(11.5))
                    .foregroundStyle(S7.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ConvertingPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group7(title: "Quality") {
                VStack(alignment: .leading, spacing: 5) {
                    Field7(label: "JPEG quality") {
                        Text("\(Int(model.quality * 100))%")
                            .font(S7.data(12)).foregroundStyle(S7.black)
                    }
                    Slider(value: $model.quality, in: 0.3...1.0)
                        .tint(S7.black)
                    HStack {
                        Text("Smaller").font(S7.read(11)).foregroundStyle(S7.faint)
                        Spacer()
                        Text("Better").font(S7.read(11)).foregroundStyle(S7.faint)
                    }
                }

                Rectangle().fill(S7.black).frame(height: 1).padding(.vertical, 3)

                Text("PDF pages render at")
                    .font(S7.read(13)).foregroundStyle(S7.black)
                ForEach([(1.0, "Screen — 72 dpi"), (2.0, "Retina — 144 dpi"), (3.0, "Print — 216 dpi")],
                        id: \.0) { scale, label in
                    S7Radio(title: label, isOn: model.rasterScale == scale) {
                        model.rasterScale = scale
                    }
                }
            }

            Group7(title: "Long jobs",
                   footer: "Long videos and PDFs of many pages take a while and produce a differently named file, so Suffix checks first.") {
                Toggle("Ask before long jobs", isOn: $model.confirmLarge)
                    .toggleStyle(S7CheckboxStyle())
            }

            Group7(title: "MP3",
                   footer: ExternalEncoder.mp3Encoder() == nil
                        ? "macOS cannot write MP3. Install ffmpeg (brew install ffmpeg) and renaming to .mp3 starts working."
                        : "macOS cannot write MP3, so Suffix uses the encoder already installed on this Mac.") {
                Field7(label: "Encoder") {
                    if let tool = ExternalEncoder.mp3Encoder() {
                        HStack(spacing: 6) {
                            Rectangle().fill(S7.green).frame(width: 9, height: 9)
                                .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                            Text(tool.name).font(S7.data(12)).foregroundStyle(S7.black)
                        }
                    } else {
                        Text("not installed").font(S7.read(12)).foregroundStyle(S7.dim)
                    }
                }
            }
        }
    }
}

/// Everything that happens in Finder rather than on a rename.
private struct ActionsPane: View {
    @ObservedObject var model: AppModel
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group7(title: "Renaming",
                   footer: "Finder asks you to confirm every extension change, before Suffix ever sees the file. Turning this off restarts Finder, which takes a moment and loses nothing.") {
                Toggle("Skip Finder's extension warning", isOn: Binding(
                    get: { !model.finderWarningShown },
                    set: { model.finderWarningShown = !$0 }))
                    .toggleStyle(S7CheckboxStyle())
            }

            Group7(title: "File actions",
                   footer: "Select files in Finder and press the shortcut, or right-click and choose Suffix: file actions. Both open the same panel: merge into one PDF, compress, or create a ZIP archive.") {
                Toggle("Enable keyboard shortcut", isOn: $model.shortcutEnabled)
                    .toggleStyle(S7CheckboxStyle())

                Field7(label: "Shortcut") {
                    Button(recording ? "Press keys…" : model.shortcut.display) {
                        recording ? stopRecording() : startRecording()
                    }
                    .buttonStyle(.s7)
                    .disabled(!model.shortcutEnabled)
                }

                if model.shortcutUnavailable {
                    HStack(spacing: 6) {
                        Rectangle().fill(S7.orange).frame(width: 9, height: 9)
                            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                        Text("Another app already uses that combination")
                            .font(S7.read(11.5)).foregroundStyle(S7.black)
                    }
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }   // Escape cancels
            guard let shortcut = Shortcut(event: event) else { return nil }
            model.shortcut = shortcut
            stopRecording()
            return nil                                              // swallow the keystroke
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// The setup checklist, still reachable afterwards.
///
/// macOS lets people revoke any of these at any time, from another app, with
/// no notification. A settings tab that shows the live answer is the only way
/// the app can explain itself when it suddenly stops working.
private struct PermissionsPane: View {
    @StateObject private var monitor = PermissionMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionList(monitor: monitor)
            Text("macOS can revoke any of these at any time. This list is measured, not remembered.")
                .font(S7.read(11.5))
                .foregroundStyle(S7.dim)
                .fixedSize(horizontal: false, vertical: true)
            PermissionAssurance()
        }
    }
}

private struct UndoPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group7(title: "Originals",
               footer: "Originals are copied aside before anything is overwritten, so any conversion can be undone from the menu bar. They live outside the folder so they don't clutter it, and are deleted automatically after a week.") {
            Toggle("Keep originals for seven days", isOn: $model.keepOriginals)
                .toggleStyle(S7CheckboxStyle())

            Field7(label: "Using") {
                Text(model.originalsSize).font(S7.data(12)).foregroundStyle(S7.black)
            }

            HStack(spacing: 10) {
                Button("Show in Finder") { model.openOriginalsFolder() }
                    .buttonStyle(.s7)
                Button("Delete all now") { model.emptyOriginals() }
                    .buttonStyle(.s7)
            }
            .padding(.top, 2)
        }
    }
}
