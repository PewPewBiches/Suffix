import Foundation
import AVFoundation

/// Video and audio, through AVFoundation.
///
/// Unlike an image, a video conversion is not instant — it can run for minutes
/// — so this reports progress and can be cancelled. That difference is the
/// reason media needed its own converter rather than another case in the image
/// one.
public struct MediaConverter {
    public struct Options: Sendable {
        /// Re-encode rather than copying the existing streams. Passthrough is
        /// near-instant and lossless, and works whenever the codecs already
        /// suit the destination container.
        public var forceReencode: Bool
        public init(forceReencode: Bool = false) { self.forceReencode = forceReencode }
    }

    let options: Options
    public init(options: Options = .init()) { self.options = options }

    /// Convert `url` into `target`, writing to `destination`.
    /// - Parameter progress: called with 0…1 on an arbitrary thread.
    public func run(_ url: URL,
                    from source: FileFormat,
                    to target: FileFormat,
                    destination: URL,
                    progress: (@Sendable (Double) -> Void)? = nil) async throws {
        // AVFoundation infers a file's type from its *extension*, unlike
        // ImageIO which reads the bytes. Since this app exists precisely
        // because the extension is wrong, the source is staged under its true
        // name first — otherwise every media conversion fails with an opaque
        // "Cannot Open".
        let staged = try Self.stage(url, as: source)
        defer { if staged != url { try? FileManager.default.removeItem(at: staged) } }
        let asset = AVURLAsset(url: staged)

        guard let outputType = target.utType.map({ AVFileType($0.identifier) }) else {
            throw ConversionError.encodingFailed(target)
        }

        let preset = try await preset(for: asset, target: target)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError.encodingFailed(target)
        }
        guard session.supportedFileTypes.contains(outputType) else {
            throw ConversionError.containerUnsupported(target)
        }

        session.outputURL = destination
        session.outputFileType = outputType

        // Extracting audio from something with no audio track cannot work, and
        // AVFoundation's own error for it says only "Operation Stopped".
        if target.family == .audio {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else { throw ConversionError.noAudioTrack }
        }

        // AVAssetExportSession is not Sendable, so progress is read through a
        // box rather than capturing the session in a detached task.
        let box = ProgressBox(session)
        let ticker = progress.map { report in
            Task.detached {
                while !Task.isCancelled {
                    report(box.value)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        defer { ticker?.cancel() }

        await session.export()

        switch session.status {
        case .completed:
            progress?(1)
        case .cancelled:
            throw ConversionError.cancelled
        default:
            throw ConversionError.mediaExportFailed(
                session.error?.localizedDescription ?? "unknown error")
        }
    }

    /// Prefer copying streams; fall back to re-encoding when the source codecs
    /// don't fit the destination container.
    private func preset(for asset: AVAsset, target: FileFormat) async throws -> String {
        if target.family == .audio {
            return AVAssetExportPresetAppleM4A
        }
        if !options.forceReencode {
            let compatible = await AVAssetExportSession.compatibility(
                ofExportPreset: AVAssetExportPresetPassthrough,
                with: asset,
                outputFileType: target.utType.map { AVFileType($0.identifier) })
            if compatible { return AVAssetExportPresetPassthrough }
        }
        return AVAssetExportPresetHighestQuality
    }

    /// Give the file its real extension in a temporary location, by hard link
    /// where possible so nothing is copied.
    static func stage(_ url: URL, as format: FileFormat) throws -> URL {
        if url.pathExtension.lowercased() == format.preferredExtension { return url }
        let fm = FileManager.default
        let staged = fm.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(format.preferredExtension)")
        do { try fm.linkItem(at: url, to: staged) }
        catch { try fm.copyItem(at: url, to: staged) }
        return staged
    }

    /// Roughly how long a job will take, used to decide whether to warn before
    /// starting one. Zero for anything that isn't time-based.
    public static func duration(of url: URL) -> Double {
        let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }
}

/// Uncompressed audio, through the `afconvert` tool that ships with macOS.
///
/// AVAssetExportSession only writes Apple's own M4A for audio, so WAV and AIFF
/// go through this instead. No installation required — it is part of the system.
public enum SystemAudio {
    /// Targets this handles, as (afconvert file format, data format).
    static func arguments(for target: FileFormat) -> (String, String)? {
        switch target {
        case .wav:  return ("WAVE", "LEI16")
        case .aiff: return ("AIFF", "BEI16")
        default:    return nil
        }
    }

    public static func canWrite(_ target: FileFormat) -> Bool { arguments(for: target) != nil }

    public static func convert(_ source: URL, to target: FileFormat, destination: URL) throws {
        guard let (fileFormat, dataFormat) = arguments(for: target) else {
            throw ConversionError.containerUnsupported(target)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", fileFormat, "-d", dataFormat, source.path, destination.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConversionError.mediaExportFailed(
                String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "afconvert failed")
        }
    }
}

/// Reads a session's progress from another task without pretending the session
/// itself is safe to share.
private final class ProgressBox: @unchecked Sendable {
    private let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    var value: Double { Double(session.progress) }
}

/// MP3, which macOS cannot write.
///
/// Rather than bundling an encoder — a binary blob plus its licence — Suffix
/// uses one already on the machine if there is one, and otherwise refuses with
/// an explanation. Most people who want MP3 output already have ffmpeg.
public enum ExternalEncoder {
    public struct Tool: Sendable {
        public let path: String
        public let name: String
    }

    private static let candidates = [
        "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg",
        "/opt/homebrew/bin/lame",   "/usr/local/bin/lame",
    ]

    /// The first usable MP3 encoder found, if any.
    public static func mp3Encoder() -> Tool? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return Tool(path: path, name: (path as NSString).lastPathComponent)
        }
        return nil
    }

    /// Decode with AVFoundation, then encode with whichever tool is present.
    public static func encodeMP3(from source: URL, to destination: URL) async throws {
        guard let tool = mp3Encoder() else {
            throw ConversionError.needsExternalTool(
                "MP3 needs ffmpeg or lame installed — try: brew install ffmpeg")
        }

        if tool.name == "ffmpeg" {
            try run(tool.path, ["-y", "-loglevel", "error", "-i", source.path, destination.path])
            return
        }

        // lame only reads WAV, so decode to a temporary one first.
        let wav = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16", source.path, wav.path])
        try run(tool.path, ["--quiet", "-h", wav.path, destination.path])
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConversionError.mediaExportFailed(
                String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "encoder failed")
        }
    }
}
