import SwiftUI
import ConvertKit

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Convert on rename", isOn: $model.enabled)
            .toggleStyle(.checkbox)

        Divider()

        if model.history.isEmpty {
            Text("No conversions yet")
                .foregroundStyle(.secondary)
            Text("Rename a file's extension in Finder to convert it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            Section("Recent") {
                ForEach(model.history.prefix(8)) { entry in
                    Menu(entry.finalURL.lastPathComponent) {
                        Text(entry.summary)
                        Button("Show in Finder") { model.reveal(entry) }
                        if entry.canUndo {
                            Button("Undo — put \(entry.originalName) back") {
                                model.undo(entry)
                            }
                        }
                    }
                }
            }
        }

        if let error = model.lastError {
            Divider()
            Text(error).foregroundStyle(.red)
        }

        Divider()

        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Rename") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Watching") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }))
                Toggle("Include external drives", isOn: $model.includeVolumes)
                Text(model.isWatching
                     ? "Watching \(model.watchRoots.map(\.lastPathComponent).joined(separator: ", "))"
                     : "Not watching")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Conversion") {
                Slider(value: $model.quality, in: 0.3...1.0) {
                    Text("JPEG quality")
                } minimumValueLabel: {
                    Text("Small").font(.caption)
                } maximumValueLabel: {
                    Text("Best").font(.caption)
                }

                Picker("PDF page resolution", selection: $model.rasterScale) {
                    Text("Screen (72 dpi)").tag(1.0)
                    Text("Retina (144 dpi)").tag(2.0)
                    Text("Print (216 dpi)").tag(3.0)
                }

                Toggle("Ask before converting long PDFs", isOn: $model.confirmLarge)
            }

            Section("Originals") {
                Toggle("Keep originals so conversions can be undone",
                       isOn: $model.keepOriginals)
                LabeledContent("Currently stored", value: model.originalsSize)
                HStack {
                    Button("Show in Finder") { model.openOriginalsFolder() }
                    Button("Delete all") { model.emptyOriginals() }
                }
                Text("Originals are deleted automatically after a week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
