import SwiftUI
import AppKit
import ConvertKit

/// The window shown when you compress a selection.
///
/// Compression needs a decision — how much quality to trade — and a filename
/// cannot carry one. The estimate is measured, not guessed: the first file is
/// actually compressed at the chosen setting and its ratio applied to the rest,
/// so the number moves when the slider does.
@MainActor
final class CompressPanel {
    static let shared = CompressPanel()
    private var window: NSWindow?

    func show(files: [URL], completion: @escaping ([CompressionResult]) -> Void) {
        window?.close()

        let view = CompressView(files: files) { [weak self] results in
            self?.window?.close()
            self?.window = nil
            completion(results)
        }

        // Borderless: the panel draws its own System 7 title bar.
        let window = S7WindowHost(size: NSSize(width: 452, height: 346))
        window.contentView = NSHostingView(rootView: view)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// The three settings people actually want, before the slider.
enum CompressionLevel: String, CaseIterable, Identifiable {
    case small, balanced, best

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:    return "Smallest"
        case .balanced: return "Balanced"
        case .best:     return "Best quality"
        }
    }

    var settings: CompressionSettings {
        switch self {
        case .small:    return .small
        case .balanced: return .balanced
        case .best:     return .gentle
        }
    }

    /// The level a given quality corresponds to, so the toggle stays in step
    /// with the slider rather than the two disagreeing.
    static func matching(quality: Double) -> CompressionLevel? {
        allCases.first { abs($0.settings.quality - quality) < 0.001 }
    }
}

struct CompressView: View {
    let files: [URL]
    let finish: ([CompressionResult]) -> Void

    @State private var level: CompressionLevel? = .balanced
    @State private var quality: Double = CompressionSettings.balanced.quality
    @State private var estimate: Int64?
    @State private var estimating = false
    @State private var working = false
    @State private var estimateTask: Task<Void, Never>?

    private var totalBefore: Int64 {
        files.reduce(0) { $0 + Compressor.size(of: $1) }
    }

    var body: some View {
        ZStack {
            S7Desktop()
            S7Window(title: "Compress", close: { finish([]) }) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(files.count == 1 ? files[0].lastPathComponent : "\(files.count) files")
                            .font(S7.data(13))
                            .foregroundStyle(S7.black)
                            .lineLimit(1).truncationMode(.middle)
                        Text(byteText(totalBefore))
                            .font(S7.read(11.5))
                            .foregroundStyle(S7.dim)
                    }

                    S7Rule()

                    // The three presets, as one segmented row of System 7 tabs.
                    HStack(spacing: 0) {
                        ForEach(CompressionLevel.allCases) { option in
                            Button {
                                level = option
                                quality = option.settings.quality
                                scheduleEstimate()
                            } label: {
                                Text(option.title)
                                    .font(S7.chrome(11))
                                    .foregroundStyle(level == option ? S7.white : S7.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(level == option ? S7.black : S7.white)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if option != CompressionLevel.allCases.last {
                                Rectangle().fill(S7.black).frame(width: 1)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Quality").font(S7.read(12.5)).foregroundStyle(S7.black)
                            Spacer()
                            Text("\(Int(quality * 100))%")
                                .font(S7.data(12)).foregroundStyle(S7.black)
                        }
                        Slider(value: $quality, in: 0.2...0.95) { } onEditingChanged: { editing in
                            if !editing { scheduleEstimate() }
                        }
                        .tint(S7.black)
                        .onChange(of: quality) { _, new in
                            // Moving the slider leaves the preset behind unless
                            // it happens to land exactly on one.
                            level = CompressionLevel.matching(quality: new)
                        }
                        HStack {
                            Text("Smaller").font(S7.read(11)).foregroundStyle(S7.faint)
                            Spacer()
                            Text("Better").font(S7.read(11)).foregroundStyle(S7.faint)
                        }
                    }

                    S7Note {
                        if estimating {
                            Text("Measuring…").font(S7.read(12)).foregroundStyle(S7.dim)
                        } else if let estimate {
                            let saved = max(0, totalBefore - estimate)
                            let percent = totalBefore > 0
                                ? Int(Double(saved) / Double(totalBefore) * 100) : 0
                            HStack(spacing: 6) {
                                Text("About").font(S7.read(12.5)).foregroundStyle(S7.black)
                                S7Selection(text: byteText(estimate))
                                Text("— saves \(percent)%")
                                    .font(S7.read(12.5)).foregroundStyle(S7.black)
                            }
                        } else {
                            Text("Estimating from the first file")
                                .font(S7.read(12)).foregroundStyle(S7.faint)
                        }
                    }

                    Spacer(minLength: 0)

                    HStack {
                        Button("Cancel") { finish([]) }
                            .buttonStyle(.s7)
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(working ? "Compressing…" : "Compress") { run() }
                            .buttonStyle(.s7Default)
                            .keyboardShortcut(.defaultAction)
                            .disabled(working)
                    }
                }
                .padding(16)
                .frame(width: 420, height: 290, alignment: .topLeading)
            }
            .padding(14)
        }
        .frame(width: 452, height: 346)
        .background(S7.paper)
        .task { scheduleEstimate() }
    }

    /// Measure a real ratio by compressing the first file, debounced so
    /// dragging the slider doesn't start a job per pixel.
    private func scheduleEstimate() {
        estimateTask?.cancel()
        let settings = CompressionSettings(quality: quality,
                                           maxDimension: (level ?? .balanced).settings.maxDimension)
        let sample = files.first
        let total = totalBefore
        estimateTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let sample else { return }
            estimating = true
            defer { estimating = false }

            let measured: Int64? = await Task.detached(priority: .userInitiated) {
                let scratch = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).jpg")
                defer { try? FileManager.default.removeItem(at: scratch) }
                guard let result = try? Compressor.compress(sample, settings: settings,
                                                            destination: scratch) else { return nil }
                return result.after
            }.value

            guard !Task.isCancelled, let measured else { return }
            let sampleBefore = Compressor.size(of: sample)
            let ratio = sampleBefore > 0 ? Double(measured) / Double(sampleBefore) : 1
            estimate = Int64(Double(total) * ratio)
        }
    }

    private func run() {
        working = true
        let settings = CompressionSettings(quality: quality,
                                           maxDimension: (level ?? .balanced).settings.maxDimension)
        let urls = files
        Task.detached(priority: .userInitiated) {
            var results: [CompressionResult] = []
            for url in urls {
                let directory = url.deletingLastPathComponent()
                let stem = url.deletingPathExtension().lastPathComponent
                let isPDF = FileFormat.detect(at: url) == .pdf
                let destination = uniqueDestination(in: directory,
                                                    stem: "\(stem) (compressed)",
                                                    ext: isPDF ? "pdf" : "jpg")
                if let result = try? Compressor.compress(url, settings: settings,
                                                         destination: destination) {
                    // Re-encoding a small file can make it larger; don't leave
                    // that lying around pretending to be an improvement.
                    if result.isWorthKeeping {
                        results.append(CompressionResult(url: destination,
                                                         before: result.before,
                                                         after: result.after))
                    } else {
                        try? FileManager.default.removeItem(at: destination)
                    }
                }
            }
            let final = results
            await MainActor.run { finish(final) }
        }
    }

    private func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
