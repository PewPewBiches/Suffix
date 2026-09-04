import Foundation
import SwiftUI
import ConvertKit
import ServiceManagement

/// Everything the menu bar shows and controls.
@MainActor
final class AppModel: ObservableObject {
    /// One instance, so the app delegate and the scenes share state.
    static let shared = AppModel()

    @Published private(set) var isWatching = false
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var lastError: String?

    @AppStorage("enabled")        var enabled = true      { didSet { syncWatching() } }
    @AppStorage("keepOriginals")  var keepOriginals = true { didSet { pushOptions() } }
    @AppStorage("quality")        var quality = 0.9        { didSet { pushOptions() } }
    @AppStorage("rasterScale")    var rasterScale = 2.0    { didSet { pushOptions() } }
    @AppStorage("confirmLarge")   var confirmLarge = true  { didSet { pushOptions() } }
    /// Watch external drives as well as the home folder.
    @AppStorage("includeVolumes") var includeVolumes = true { didSet { restartWatching() } }
    /// Replace the renamed file, or leave the original beside the result.
    @AppStorage("outputMode")     var outputMode = OutputMode.replace { didSet { pushOptions() } }
    @AppStorage("hasOnboarded")   var hasOnboarded = false

    /// Registered with the system rather than stored by us, so the toggle
    /// reflects reality even if the user changes it in System Settings.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                newValue ? try SMAppService.mainApp.register()
                         : try SMAppService.mainApp.unregister()
            } catch {
                lastError = "Could not change launch at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    private let service = ConversionService()
    private var watcher: RenameWatcher?

    init() {
        pushOptions()
        OriginalsStore.prune()
        syncWatching()
    }

    var watchRoots: [URL] {
        var roots = [URL(fileURLWithPath: NSHomeDirectory())]
        if includeVolumes { roots.append(URL(fileURLWithPath: "/Volumes")) }
        return roots
    }

    var originalsSize: String {
        ByteCountFormatter.string(fromByteCount: OriginalsStore.size(), countStyle: .file)
    }

    // MARK: - Watching

    private func syncWatching() {
        enabled ? startWatching() : stopWatching()
    }

    private func restartWatching() {
        guard isWatching else { return }
        stopWatching(); startWatching()
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let w = RenameWatcher(roots: watchRoots) { [weak self] url in
            Task { @MainActor in self?.handleRename(url) }
        }
        w.start()
        watcher = w
        isWatching = true
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        isWatching = false
    }

    // MARK: - Reacting

    private func handleRename(_ url: URL) {
        switch service.decide(url) {
        case .ignore:
            return
        case .convert(let plan):
            run(plan, on: url)
        case .confirm(let plan):
            guard Confirmation.ask(plan: plan, file: url) else { return }
            run(plan, on: url)
        }
    }

    private func run(_ plan: ConversionPlan, on url: URL) {
        let originalName = url.lastPathComponent
        Task.detached(priority: .userInitiated) { [service] in
            do {
                let result = try service.perform(plan, on: url)
                await MainActor.run {
                    self.history = service.history
                    self.lastError = nil
                    self.announce(result, originalName: originalName)
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    NoticeCenter.shared.show(Notice(
                        title: "Couldn't convert \(originalName)",
                        detail: error.localizedDescription,
                        isError: true))
                }
            }
        }
    }

    private func announce(_ result: ConversionResult, originalName: String) {
        let entry = service.history.first
        NoticeCenter.shared.show(Notice(
            title: "Converted",
            from: originalName,
            to: result.finalURL.lastPathComponent,
            detail: result.keptAlongside.map { "\($0.lastPathComponent) kept alongside" },
            thumbnail: Thumbnail.image(for: result.finalURL),
            undo: entry.flatMap { e in e.canUndo ? { [weak self] in self?.undo(e) } : nil },
            reveal: { [weak self] in
                _ = self
                NSWorkspace.shared.activateFileViewerSelecting([result.finalURL])
            }))
    }

    // MARK: - Actions the menu offers

    func undo(_ entry: HistoryEntry) {
        do {
            try service.undo(entry)
            history = service.history
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reveal(_ entry: HistoryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.finalURL])
    }

    func openOriginalsFolder() {
        try? FileManager.default.createDirectory(
            at: OriginalsStore.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(OriginalsStore.root)
    }

    func emptyOriginals() {
        try? FileManager.default.removeItem(at: OriginalsStore.root)
        objectWillChange.send()
    }

    private func pushOptions() {
        service.options = ConversionOptions(quality: quality,
                                            rasterScale: rasterScale,
                                            keepOriginal: keepOriginals,
                                            outputMode: outputMode)
        service.confirmLargeJobs = confirmLarge
    }
}
