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

    /// Read from Finder's own preference, so the toggle stays truthful even if
    /// the user changes it in Finder's settings instead.
    var finderWarningShown: Bool {
        get { FinderWarning.isShown }
        set {
            FinderWarning.setShown(newValue)
            objectWillChange.send()
        }
    }

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
    private var positionTimer: Timer?

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

    private static let lastEventKey = "lastEventId"

    private func startWatching() {
        guard watcher == nil else { return }

        // Resume from where the last run stopped, so renames made while the
        // app was launching (or closed) are not simply lost. The watcher's own
        // age guard stops this replaying anything stale.
        let stored = UserDefaults.standard.object(forKey: Self.lastEventKey) as? NSNumber
        let w = RenameWatcher(roots: watchRoots,
                              since: stored.map { FSEventStreamEventId($0.uint64Value) }) { [weak self] url in
            Task { @MainActor in self?.handleRename(url) }
        }
        w.start()
        watcher = w
        isWatching = true

        // Save the position as we go. Relying on termination alone loses it
        // whenever the app is killed rather than quit, which is exactly the
        // case where resuming matters.
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in self.rememberPosition() }
        }
    }

    private func stopWatching() {
        positionTimer?.invalidate()
        positionTimer = nil
        rememberPosition()
        watcher?.stop()
        watcher = nil
        isWatching = false
    }

    /// Store the stream position so the next launch can pick up from it.
    func rememberPosition() {
        guard let watcher, watcher.lastEventId > 0 else { return }
        UserDefaults.standard.set(NSNumber(value: UInt64(watcher.lastEventId)),
                                  forKey: Self.lastEventKey)
    }

    // MARK: - Reacting

    /// Inspecting a renamed file reads it, and the first read inside a
    /// protected folder can raise a macOS permission prompt that blocks the
    /// calling thread until the user answers. Doing that on the main thread
    /// froze the whole app — menu bar included — with no visible cause, so
    /// inspection happens off it and only the decision comes back.
    private func handleRename(_ url: URL) {
        Task.detached(priority: .utility) { [service] in
            let decision = service.decide(url)
            await MainActor.run { self.act(on: decision, url: url) }
        }
    }

    private func act(on decision: Decision, url: URL) {
        Log.write("decision for \(url.lastPathComponent): \(decision)")
        switch decision {
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
        Log.write("run \(plan.summary) on \(originalName)")
        Task.detached(priority: .userInitiated) { [service] in
            do {
                let result = try service.perform(plan, on: url)
                Log.write("converted \(originalName) -> \(result.finalURL.lastPathComponent)")
                await MainActor.run {
                    self.history = service.history
                    self.lastError = nil
                    self.announce(result, originalName: originalName)
                }
            } catch {
                Log.write("FAILED \(originalName): \(error.localizedDescription)")
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
