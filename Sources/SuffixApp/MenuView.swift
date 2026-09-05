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
/// built and, more usefully, let each pane be read on its own.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralPane(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            ConvertingPane(model: model)
                .tabItem { Label("Converting", systemImage: "arrow.triangle.2.circlepath") }
            ActionsPane(model: model)
                .tabItem { Label("Finder", systemImage: "folder") }
            PermissionsPane()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            UndoPane(model: model)
                .tabItem { Label("Undo", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 480)
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Convert files when I rename them", isOn: $model.enabled)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }))
                Toggle("Watch external drives too", isOn: $model.includeVolumes)
                LabeledContent("Status") {
                    Label(model.isWatching ? "Watching your files" : "Paused",
                          systemImage: model.isWatching ? "checkmark.circle.fill" : "pause.circle.fill")
                        .foregroundStyle(model.isWatching ? Style.accent : .secondary)
                        .font(.callout).fontWeight(.medium)
                }
            } footer: {
                Text("Suffix only acts when a file's new extension is one it can produce and the contents don't already match.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("When a file converts") {
                OutputModePicker(mode: $model.outputMode)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ConvertingPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Quality") {
                Slider(value: $model.quality, in: 0.3...1.0) {
                    Text("JPEG quality")
                } minimumValueLabel: {
                    Text("Smaller").font(.caption)
                } maximumValueLabel: {
                    Text("Better").font(.caption)
                }
                Picker("PDF pages render at", selection: $model.rasterScale) {
                    Text("Screen — 72 dpi").tag(1.0)
                    Text("Retina — 144 dpi").tag(2.0)
                    Text("Print — 216 dpi").tag(3.0)
                }
            }

            Section {
                Toggle("Ask before long jobs", isOn: $model.confirmLarge)
            } footer: {
                Text("Long videos and PDFs of many pages take a while and produce a differently named file, so Suffix checks first.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("MP3 encoder") {
                    if let tool = ExternalEncoder.mp3Encoder() {
                        Label(tool.name, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Style.accent).font(.callout)
                    } else {
                        Text("not installed").foregroundStyle(.secondary).font(.callout)
                    }
                }
            } footer: {
                Text(ExternalEncoder.mp3Encoder() == nil
                     ? "macOS cannot write MP3. Install ffmpeg (brew install ffmpeg) and renaming to .mp3 will start working."
                     : "macOS cannot write MP3, so Suffix uses the encoder already installed on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Everything that happens in Finder rather than on a rename.
private struct ActionsPane: View {
    @ObservedObject var model: AppModel
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Form {
            Section {
                Toggle("Skip Finder's extension warning", isOn: Binding(
                    get: { !model.finderWarningShown },
                    set: { model.finderWarningShown = !$0 }))
            } header: {
                Text("Renaming")
            } footer: {
                Text("Finder asks you to confirm every extension change, before Suffix ever sees the file. Turning this off restarts Finder, which takes a moment and loses nothing.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable keyboard shortcut", isOn: $model.shortcutEnabled)
                LabeledContent("Shortcut") {
                    Button(recording ? "Press keys…" : model.shortcut.display) {
                        recording ? stopRecording() : startRecording()
                    }
                    .font(.body.monospaced())
                    .disabled(!model.shortcutEnabled)
                }
                if model.shortcutUnavailable {
                    Label("Another app already uses that combination",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("File actions")
            } footer: {
                Text("Select files in Finder and press the shortcut, or right-click and choose Suffix: file actions. Both open the same panel: merge into one PDF, compress, or create a ZIP archive.\n\nThe shortcut asks Finder what you've selected, so macOS will ask permission the first time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PermissionList(monitor: monitor)

                Text("Open a row for what it is used for and what it does not allow. macOS can revoke any of these at any time — this list is measured, not remembered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.4)
                PermissionAssurance()
            }
            .padding(20)
        }
        .frame(minHeight: 380)
    }
}

private struct UndoPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Keep originals for seven days", isOn: $model.keepOriginals)
                LabeledContent("Using", value: model.originalsSize)
                HStack {
                    Button("Show in Finder") { model.openOriginalsFolder() }
                    Button("Delete all now") { model.emptyOriginals() }
                }
            } footer: {
                Text("Originals are copied aside before anything is overwritten, so any conversion can be undone from the menu bar. They live outside the folder so they don't clutter it, and are deleted automatically after a week.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
