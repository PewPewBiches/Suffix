import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ConvertKit

// MARK: - Helpers

/// Write a tiny real image of `format` to a temp file.
private func makeImage(_ format: FileFormat, named name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConvertKitTests/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)

    let w = 8, h = 8
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(gray: 0.5, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let image = ctx.makeImage()!

    let dest = CGImageDestinationCreateWithURL(
        url as CFURL, format.utType.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    #expect(CGImageDestinationFinalize(dest))
    return url
}

private func plan(source: FileFormat?, ext: String, pages: Int = 1)
    -> Result<ConversionPlan, ConversionPlan.Refusal> {
    ConversionPlan.make(source: source, targetExtension: ext, pageCount: { pages })
}

// MARK: - Format identity

@Test("extensions map to the format the user meant")
func extensionMapping() {
    #expect(FileFormat.forExtension("jpg") == .jpeg)
    #expect(FileFormat.forExtension("JPEG") == .jpeg)     // case-insensitive
    #expect(FileFormat.forExtension("tif") == .tiff)
    #expect(FileFormat.forExtension("heif") == .heic)
    #expect(FileFormat.forExtension("xyz") == nil)
}

@Test("detection reads bytes, not the filename")
func detectionIgnoresName() throws {
    // A PNG deliberately misnamed .jpg — the exact case this whole app exists for.
    let url = try makeImage(.png, named: "lying.jpg")
    #expect(FileFormat.detect(at: url) == .png)
}

@Test("non-images are not mistaken for images")
func detectionRejectsJunk() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConvertKitTests/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("notes.jpg")
    try "just some text".write(to: url, atomically: true, encoding: .utf8)
    #expect(FileFormat.detect(at: url) == nil)
}

// MARK: - Planning

@Test("raster to raster re-encodes")
func planReencode() throws {
    #expect(try plan(source: .png, ext: "jpg").get() == .reencode(from: .png, to: .jpeg))
}

@Test("image to pdf wraps")
func planImageToPDF() throws {
    #expect(try plan(source: .jpeg, ext: "pdf").get() == .imagesToPDF(from: .jpeg))
}

@Test("a one-page pdf becomes a single image")
func planSinglePagePDF() throws {
    #expect(try plan(source: .pdf, ext: "png", pages: 1).get() == .pdfToImage(to: .png, pages: 1))
}

@Test("a multi-page pdf becomes a zip, and asks first")
func planMultiPagePDF() throws {
    let p = try plan(source: .pdf, ext: "jpg", pages: 100).get()
    #expect(p == .pdfToImageArchive(to: .jpeg, pages: 100))
    #expect(p.needsConfirmation)
}

@Test("a same-format rename is not a conversion")
func planSameFormat() {
    #expect(plan(source: .jpeg, ext: "jpeg") == .failure(.sameFormat(.jpeg)))
    // .jpg -> .jpeg is a rename between spellings of one format, not work.
    #expect(plan(source: .jpeg, ext: "jpg") == .failure(.sameFormat(.jpeg)))
}

@Test("unreadable sources and unknown targets are refused, not guessed")
func planRefusals() {
    #expect(plan(source: nil, ext: "png") == .failure(.unreadableSource))
    #expect(plan(source: .png, ext: "xyz") == .failure(.unknownTargetExtension("xyz")))
    // WebP is readable on macOS but not writable, so it must be refused up front.
    #expect(plan(source: .png, ext: "webp") == .failure(.unwritableTarget(.webp)))
}

// MARK: - Converting

@Test("converting produces the target format in place")
func convertInPlace() throws {
    let url = try makeImage(.png, named: "shot.jpg")
    let p = try plan(source: .png, ext: "jpg").get()
    let result = try Converter(options: .init(keepOriginal: false)).run(p, on: url)
    #expect(result.finalURL == url)
    #expect(FileFormat.detect(at: url) == .jpeg)
}

@Test("image to pdf yields a real pdf")
func convertToPDF() throws {
    let url = try makeImage(.png, named: "scan.pdf")
    let p = try plan(source: .png, ext: "pdf").get()
    _ = try Converter(options: .init(keepOriginal: false)).run(p, on: url)
    #expect(FileFormat.detect(at: url) == .pdf)
}

@Test("the original is stashed with its true extension, so it stays openable")
func backupKeepsRealExtension() throws {
    let url = try makeImage(.png, named: "photo.jpg")   // PNG bytes, .jpg name
    let p = try plan(source: .png, ext: "jpg").get()
    let result = try Converter(options: .init(keepOriginal: true)).run(p, on: url)
    let backup = try #require(result.originalBackup)
    #expect(backup.pathExtension == "png")
    #expect(FileFormat.detect(at: backup) == .png)
    try? FileManager.default.removeItem(at: backup)
}

@Test("pruning removes stale originals and keeps fresh ones")
func pruning() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConvertKitTests/prune-\(UUID().uuidString)")
    let saved = OriginalsStore.root
    OriginalsStore.root = root
    defer { OriginalsStore.root = saved; try? FileManager.default.removeItem(at: root) }

    let fm = FileManager.default
    let old = root.appendingPathComponent("2020-01-01")
    let new = root.appendingPathComponent(dayStamp(Date()))
    try fm.createDirectory(at: old, withIntermediateDirectories: true)
    try fm.createDirectory(at: new, withIntermediateDirectories: true)

    OriginalsStore.prune()
    #expect(!fm.fileExists(atPath: old.path))
    #expect(fm.fileExists(atPath: new.path))
}
