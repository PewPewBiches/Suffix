import Foundation
import ImageIO
import PDFKit
import CoreGraphics
import UniformTypeIdentifiers

public struct ConversionOptions: Sendable {
    /// JPEG/HEIC quality, 0…1.
    public var quality: Double
    /// Points-per-point scale when rasterising a PDF. 2.0 ≈ Retina.
    public var rasterScale: Double
    /// Keep a copy of the original so the conversion can be undone.
    public var keepOriginal: Bool

    public init(quality: Double = 0.9, rasterScale: Double = 2.0, keepOriginal: Bool = true) {
        self.quality = quality
        self.rasterScale = rasterScale
        self.keepOriginal = keepOriginal
    }
}

public struct ConversionResult: Sendable {
    /// Where the converted file ended up. Usually the path the user typed, but
    /// a multi-page PDF becomes a .zip, so the extension can differ.
    public let finalURL: URL
    /// Where the original was stashed, if it was kept.
    public let originalBackup: URL?
    public let plan: ConversionPlan
}

public enum ConversionError: LocalizedError {
    case cannotRead(URL)
    case encodingFailed(FileFormat)
    case pdfRenderFailed(page: Int)
    case archiveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotRead(let u):     return "Could not read \(u.lastPathComponent)."
        case .encodingFailed(let f): return "Could not encode as \(f.displayName)."
        case .pdfRenderFailed(let p): return "Could not render page \(p)."
        case .archiveFailed(let m):  return "Could not build the archive: \(m)"
        }
    }
}

public struct Converter {
    let options: ConversionOptions
    public init(options: ConversionOptions = .init()) { self.options = options }

    /// Convert `url` in place, according to `plan`.
    public func run(_ plan: ConversionPlan, on url: URL) throws -> ConversionResult {
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let backup = options.keepOriginal ? try OriginalsStore.stash(url) : nil

        switch plan {
        case .reencode(_, let target):
            let data = try reencode(url, to: target)
            try replace(url, with: data)
            return .init(finalURL: url, originalBackup: backup, plan: plan)

        case .imagesToPDF:
            let data = try imageToPDF(url)
            try replace(url, with: data)
            return .init(finalURL: url, originalBackup: backup, plan: plan)

        case .pdfToImage(let target, _):
            let pages = try renderPDF(url, to: target)
            guard let first = pages.first else { throw ConversionError.pdfRenderFailed(page: 1) }
            try replace(url, with: first)
            return .init(finalURL: url, originalBackup: backup, plan: plan)

        case .pdfToImageArchive(let target, _):
            let pages = try renderPDF(url, to: target)
            let zipURL = try archive(pages, named: stem, ext: target.preferredExtension, in: dir)
            // The renamed file was only ever a placeholder for the request.
            try? FileManager.default.removeItem(at: url)
            return .init(finalURL: zipURL, originalBackup: backup, plan: plan)
        }
    }

    // MARK: - Raster → raster

    private func reencode(_ url: URL, to target: FileFormat) throws -> Data {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ConversionError.cannotRead(url) }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, target.utType.identifier as CFString, 1, nil)
        else { throw ConversionError.encodingFailed(target) }

        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: options.quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConversionError.encodingFailed(target) }
        return out as Data
    }

    // MARK: - Image → PDF

    private func imageToPDF(_ url: URL) throws -> Data {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ConversionError.cannotRead(url) }

        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw ConversionError.encodingFailed(.pdf) }

        ctx.beginPDFPage(nil)
        ctx.draw(image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    // MARK: - PDF → raster

    private func renderPDF(_ url: URL, to target: FileFormat) throws -> [Data] {
        guard let doc = PDFDocument(url: url) else { throw ConversionError.cannotRead(url) }
        let scale = CGFloat(options.rasterScale)
        var pages: [Data] = []

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { throw ConversionError.pdfRenderFailed(page: i + 1) }
            let bounds = page.bounds(for: .mediaBox)
            let w = Int((bounds.width * scale).rounded()), h = Int((bounds.height * scale).rounded())
            guard w > 0, h > 0,
                  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { throw ConversionError.pdfRenderFailed(page: i + 1) }

            // PDF pages are transparent; flatten onto white so JPEG isn't black.
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: ctx)

            guard let image = ctx.makeImage() else { throw ConversionError.pdfRenderFailed(page: i + 1) }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                out, target.utType.identifier as CFString, 1, nil)
            else { throw ConversionError.encodingFailed(target) }
            CGImageDestinationAddImage(dest, image, [
                kCGImageDestinationLossyCompressionQuality: options.quality
            ] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw ConversionError.encodingFailed(target) }
            pages.append(out as Data)
        }
        return pages
    }

    // MARK: - Plumbing

    /// Write `data` over `url` without leaving a half-written file behind.
    private func replace(_ url: URL, with data: Data) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// Build a .zip of the rendered pages, avoiding a name collision.
    private func archive(_ pages: [Data], named stem: String, ext: String, in dir: URL) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let width = max(3, String(pages.count).count)
        for (i, data) in pages.enumerated() {
            let name = "\(stem)-\(String(format: "%0\(width)d", i + 1)).\(ext)"
            try data.write(to: staging.appendingPathComponent(name))
        }

        let zipURL = uniqueURL(in: dir, stem: stem, ext: "zip")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // -X drops the __MACOSX/resource-fork noise; -j flattens the staging dir.
        proc.arguments = ["-q", "-X", "-j", "-r", zipURL.path, staging.path]
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ConversionError.archiveFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return zipURL
    }

    private func uniqueURL(in dir: URL, stem: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(stem).\(ext)")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
