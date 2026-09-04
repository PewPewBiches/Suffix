import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Things you do to several files at once.
///
/// These cannot be expressed as a rename — "merge these three" has no filename
/// to type it into, and "compress this" needs a quality that a filename cannot
/// carry. They belong in Finder's right-click menu instead, which is why they
/// live apart from the rename engine.
public enum BatchOperation: String, Sendable, CaseIterable, Identifiable {
    case mergePDF
    case compress
    case zip

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mergePDF: return "Merge into one PDF"
        case .compress: return "Compress…"
        case .zip:      return "Create ZIP archive"
        }
    }

    /// Whether a set of files can be handled by this operation at all.
    public func accepts(_ formats: [FileFormat?]) -> Bool {
        switch self {
        case .mergePDF:
            // Pages come from PDFs and from images; anything else has no pages.
            return formats.allSatisfy { $0 == .pdf || $0?.family == .image } && formats.count >= 1
        case .compress:
            return formats.allSatisfy { $0 == .pdf || $0?.family == .image }
        case .zip:
            return true
        }
    }
}

public enum BatchError: LocalizedError {
    case nothingToDo
    case unreadable(URL)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .nothingToDo:      return "Nothing to work with."
        case .unreadable(let u): return "Could not read \(u.lastPathComponent)."
        case .failed(let m):    return m
        }
    }
}

// MARK: - Merging

public enum PDFMerge {
    /// Combine PDFs and images into a single document, in the order given.
    ///
    /// Finder hands over a selection in its own display order, which is the
    /// order the user can see — so it is kept rather than re-sorted.
    public static func merge(_ urls: [URL], to destination: URL) throws {
        guard !urls.isEmpty else { throw BatchError.nothingToDo }
        let output = PDFDocument()
        var pageIndex = 0

        for url in urls {
            switch FileFormat.detect(at: url) {
            case .pdf:
                guard let document = PDFDocument(url: url) else { throw BatchError.unreadable(url) }
                for i in 0..<document.pageCount {
                    guard let page = document.page(at: i) else { continue }
                    output.insert(page, at: pageIndex)
                    pageIndex += 1
                }
            case .some(let format) where format.family == .image:
                guard let image = NSImage(contentsOf: url),
                      let page = PDFPage(image: image) else { throw BatchError.unreadable(url) }
                output.insert(page, at: pageIndex)
                pageIndex += 1
            default:
                throw BatchError.unreadable(url)
            }
        }

        guard output.pageCount > 0 else { throw BatchError.nothingToDo }
        guard output.write(to: destination) else {
            throw BatchError.failed("Could not write the merged PDF.")
        }
    }

    /// A name for the result: the shared beginning of the selection where there
    /// is one, so `invoice-1.pdf` and `invoice-2.pdf` become `invoice.pdf`.
    public static func suggestedName(for urls: [URL]) -> String {
        let stems = urls.map { $0.deletingPathExtension().lastPathComponent }
        guard let first = stems.first else { return "Merged" }
        var prefix = first
        for stem in stems.dropFirst() {
            prefix = String(zip(prefix, stem).prefix { $0 == $1 }.map(\.0))
        }
        let trimmed = prefix.trimmingCharacters(in: CharacterSet(charactersIn: " -_·,("))
        return trimmed.count >= 3 ? trimmed : "Merged"
    }
}

// MARK: - Compressing

public struct CompressionSettings: Sendable {
    /// JPEG quality, 0…1.
    public var quality: Double
    /// Longest edge in pixels; images larger than this are scaled down.
    /// `nil` keeps the original dimensions.
    public var maxDimension: Int?

    public init(quality: Double = 0.6, maxDimension: Int? = 2048) {
        self.quality = quality
        self.maxDimension = maxDimension
    }

    public static let gentle  = CompressionSettings(quality: 0.8, maxDimension: nil)
    public static let balanced = CompressionSettings(quality: 0.6, maxDimension: 2400)
    public static let small   = CompressionSettings(quality: 0.4, maxDimension: 1600)
}

public struct CompressionResult: Sendable {
    public let url: URL
    public let before: Int64
    public let after: Int64

    public init(url: URL, before: Int64, after: Int64) {
        self.url = url
        self.before = before
        self.after = after
    }

    public var saved: Int64 { max(0, before - after) }
    public var ratio: Double { before > 0 ? Double(after) / Double(before) : 1 }
    /// Whether compressing actually helped. Re-encoding an already-small file
    /// can make it bigger, and shipping that silently would be a bug.
    public var isWorthKeeping: Bool { after < before }
}

public enum Compressor {
    /// Compress in place, into `destination`. Returns the sizes either side so
    /// the caller can decide whether it was worth it.
    public static func compress(_ url: URL,
                                settings: CompressionSettings,
                                destination: URL) throws -> CompressionResult {
        let before = size(of: url)
        switch FileFormat.detect(at: url) {
        case .pdf:
            try compressPDF(url, settings: settings, destination: destination)
        case .some(let format) where format.family == .image:
            try compressImage(url, settings: settings, destination: destination)
        default:
            throw BatchError.unreadable(url)
        }
        return CompressionResult(url: url, before: before, after: size(of: destination))
    }

    public static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func compressImage(_ url: URL,
                                      settings: CompressionSettings,
                                      destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw BatchError.unreadable(url)
        }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let maximum = settings.maxDimension {
            options[kCGImageSourceThumbnailMaxPixelSize] = maximum
        }
        // Thumbnail generation is the supported way to decode-and-scale in one
        // step; at full size it simply returns the original pixels.
        guard let image = settings.maxDimension == nil
                ? CGImageSourceCreateImageAtIndex(source, 0, nil)
                : CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw BatchError.unreadable(url) }

        guard let out = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw BatchError.failed("Could not write the compressed image.") }
        CGImageDestinationAddImage(out, image, [
            kCGImageDestinationLossyCompressionQuality: settings.quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(out) else {
            throw BatchError.failed("Could not write the compressed image.")
        }
    }

    /// PDFs shrink by re-rendering each page as a JPEG at a lower resolution.
    ///
    /// This is lossy and it flattens text into pixels, so it is offered as
    /// "compress", never applied automatically to a document being converted.
    private static func compressPDF(_ url: URL,
                                    settings: CompressionSettings,
                                    destination: URL) throws {
        guard let document = PDFDocument(url: url) else { throw BatchError.unreadable(url) }
        let output = PDFDocument()

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let longest = max(bounds.width, bounds.height)
            let target = Double(settings.maxDimension ?? 2048)
            let scale = min(2.0, max(0.5, target / longest))

            let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
            guard width > 0, height > 0,
                  let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { continue }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: context)

            guard let rendered = context.makeImage() else { continue }
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, rendered, [
                kCGImageDestinationLossyCompressionQuality: settings.quality,
            ] as CFDictionary)
            guard CGImageDestinationFinalize(dest),
                  let image = NSImage(data: data as Data),
                  let newPage = PDFPage(image: image) else { continue }
            newPage.setBounds(bounds, for: .mediaBox)
            output.insert(newPage, at: output.pageCount)
        }

        guard output.pageCount > 0, output.write(to: destination) else {
            throw BatchError.failed("Could not write the compressed PDF.")
        }
    }
}

// MARK: - Archiving

public enum Archiver {
    /// Zip a selection. Uses the `zip` tool with `-X` so the archive doesn't
    /// carry macOS resource-fork clutter that confuses other platforms.
    public static func zip(_ urls: [URL], to destination: URL) throws {
        guard !urls.isEmpty else { throw BatchError.nothingToDo }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = urls[0].deletingLastPathComponent()
        process.arguments = ["-q", "-X", "-r", destination.path] + urls.map(\.lastPathComponent)
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BatchError.failed(String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Could not build the archive.")
        }
    }
}

/// A free filename next to the originals, so nothing is ever overwritten.
public func uniqueDestination(in directory: URL, stem: String, ext: String) -> URL {
    let fm = FileManager.default
    var candidate = directory.appendingPathComponent("\(stem).\(ext)")
    var n = 2
    while fm.fileExists(atPath: candidate.path) {
        candidate = directory.appendingPathComponent("\(stem) \(n).\(ext)")
        n += 1
    }
    return candidate
}
