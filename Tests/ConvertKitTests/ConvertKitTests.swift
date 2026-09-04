import Testing
import Foundation
import ImageIO
import AppKit
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
        url as CFURL, format.utType!.identifier as CFString, 1, nil)!
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

@Test("a text file named .jpg is identified as text, and refused as an image")
func detectionRejectsJunk() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConvertKitTests/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("notes.jpg")
    try "just some text".write(to: url, atomically: true, encoding: .utf8)

    // Text is a format Suffix knows now, so it is identified rather than
    // unknown — but nothing sensible turns prose into a JPEG.
    #expect(FileFormat.detect(at: url) == .txt)
    #expect(plan(source: .txt, ext: "jpg") == .failure(.incompatible(from: .txt, to: .jpeg)))
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

// MARK: - Watcher filtering

@Test("system and churn directories are ignored")
func watcherExcludesNoise() {
    #expect(!RenameWatcher.isEligible(path: "/System/Library/thing.png"))
    #expect(!RenameWatcher.isEligible(path: NSHomeDirectory() + "/Library/Caches/x.png"))
    #expect(!RenameWatcher.isEligible(path: "/Users/me/proj/node_modules/a/logo.png"))
    #expect(!RenameWatcher.isEligible(path: "/Users/me/.Trash/old.png"))
    #expect(!RenameWatcher.isEligible(path: "/Users/me/proj/.git/x.png"))
}

@Test("only files we could actually convert are considered")
func watcherExtensionGate() {
    #expect(RenameWatcher.isEligible(path: "/Users/me/Desktop/photo.jpg"))
    #expect(RenameWatcher.isEligible(path: "/Users/me/Desktop/scan.pdf"))
    // .txt is a real target now (a PDF's text can be extracted to one).
    #expect(RenameWatcher.isEligible(path: "/Users/me/Desktop/notes.txt"))
    #expect(!RenameWatcher.isEligible(path: "/Users/me/Desktop/archive.zip"))
    #expect(!RenameWatcher.isEligible(path: "/Users/me/Desktop/notes.xyz"))
    #expect(!RenameWatcher.isEligible(path: "/Users/me/Desktop/.hidden.png"))
}

@Test("a rename that changes nothing is not treated as work")
func serviceIgnoresNonConversions() throws {
    let url = try makeImage(.jpeg, named: "already.jpg")
    if case .ignore = ConversionService().decide(url) {} else {
        Issue.record("a correctly-named JPEG should be ignored")
    }
}

@Test("a large PDF job asks before running")
func serviceConfirmsLargeJobs() {
    let service = ConversionService()
    let plan = ConversionPlan.pdfToImageArchive(to: .jpeg, pages: 200)
    #expect(plan.needsConfirmation)
    #expect(service.confirmLargeJobs)
}

// MARK: - Keeping both files

@Test("keepBoth leaves the original beside the result, under its true name")
func keepBothProducesTwoFiles() throws {
    let url = try makeImage(.png, named: "invoice.pdf")   // PNG bytes, .pdf name
    let p = try plan(source: .png, ext: "pdf").get()
    let result = try Converter(options: .init(keepOriginal: false, outputMode: .keepBoth))
        .run(p, on: url)

    let kept = try #require(result.keptAlongside)
    #expect(kept.lastPathComponent == "invoice.png")
    #expect(FileFormat.detect(at: kept) == .png)      // original, untouched
    #expect(FileFormat.detect(at: url) == .pdf)       // converted, as renamed
    #expect(kept.deletingLastPathComponent() == url.deletingLastPathComponent())
}

@Test("replace leaves exactly one file")
func replaceProducesOneFile() throws {
    let url = try makeImage(.png, named: "invoice.pdf")
    let p = try plan(source: .png, ext: "pdf").get()
    let result = try Converter(options: .init(keepOriginal: false, outputMode: .replace))
        .run(p, on: url)

    #expect(result.keptAlongside == nil)
    let siblings = try FileManager.default.contentsOfDirectory(
        atPath: url.deletingLastPathComponent().path)
    #expect(siblings == ["invoice.pdf"])
}

@Test("keeping both never overwrites a file that is already there")
func keepBothAvoidsCollisions() throws {
    let url = try makeImage(.png, named: "shot.jpg")
    // Something already occupies the name the original would take.
    let occupied = url.deletingLastPathComponent().appendingPathComponent("shot.png")
    try "not an image".write(to: occupied, atomically: true, encoding: .utf8)

    let p = try plan(source: .png, ext: "jpg").get()
    let result = try Converter(options: .init(keepOriginal: false, outputMode: .keepBoth))
        .run(p, on: url)

    let kept = try #require(result.keptAlongside)
    #expect(kept.lastPathComponent == "shot 2.png")
    // The pre-existing file is still intact.
    #expect(try String(contentsOf: occupied, encoding: .utf8) == "not an image")
}

@Test("both modes explain themselves with a concrete example")
func modesExplainThemselves() {
    #expect(OutputMode.keepBoth.explanation().contains("photo.png"))
    #expect(OutputMode.replace.explanation().contains("becomes"))
    #expect(OutputMode.allCases.count == 2)
}

// MARK: - Rename recency

@Test("a rename of an old file still counts as recent")
func recencyUsesCtimeNotMtime() throws {
    // The realistic case: a photo from months ago, renamed just now. Its
    // content-modification date is old; only ctime moves on a rename.
    let url = try makeImage(.png, named: "old.png")
    let longAgo = Date(timeIntervalSinceNow: -60 * 60 * 24 * 90)
    try FileManager.default.setAttributes([.modificationDate: longAgo],
                                          ofItemAtPath: url.path)

    let renamed = url.deletingLastPathComponent().appendingPathComponent("old.jpg")
    try FileManager.default.moveItem(at: url, to: renamed)

    #expect(RenameWatcher.isRecent(path: renamed.path))
}

@Test("a file untouched for a long time is not acted on")
func recencyRejectsStale() throws {
    let url = try makeImage(.png, named: "stale.jpg")
    // Nothing has happened to this file since it was written; simulate the
    // replay case by asking with a window of zero.
    let age = Date().timeIntervalSince(
        try #require(try url.resourceValues(forKeys: [.attributeModificationDateKey])
            .attributeModificationDate))
    #expect(age < RenameWatcher.maxAge)   // fresh now…
    #expect(RenameWatcher.isRecent(path: "/nonexistent/file.jpg") == false)
}

// MARK: - Media and documents

@Test("video containers convert to one another")
func planVideo() throws {
    let p = try plan(source: .mov, ext: "mp4").get()
    #expect(p == .media(from: .mov, to: .mp4, seconds: 0))
}

@Test("a long video asks before it starts, a short one doesn't")
func longMediaConfirms() {
    #expect(ConversionPlan.media(from: .mov, to: .mp4, seconds: 5).needsConfirmation == false)
    #expect(ConversionPlan.media(from: .mov, to: .mp4, seconds: 600).needsConfirmation)
}

@Test("video yields audio, but audio cannot yield video")
func planAudioExtraction() throws {
    #expect(try plan(source: .mp4, ext: "m4a").get() == .media(from: .mp4, to: .m4a, seconds: 0))
    #expect(plan(source: .m4a, ext: "mp4") == .failure(.incompatible(from: .m4a, to: .mp4)))
}

@Test("MP3 is refused with instructions when no encoder is installed")
func mp3NeedsEncoder() {
    let without = ConversionPlan.make(source: .mp4, targetExtension: "mp3",
                                      pageCount: { 0 }, mediaSeconds: { 10 },
                                      hasMP3Encoder: { false })
    guard case .failure(.needsExternalTool(let format, let hint)) = without else {
        Issue.record("expected a refusal naming the missing tool"); return
    }
    #expect(format == .mp3)
    #expect(hint.contains("ffmpeg"))

    // With one present it plans normally.
    let with = ConversionPlan.make(source: .mp4, targetExtension: "mp3",
                                   pageCount: { 0 }, mediaSeconds: { 10 },
                                   hasMP3Encoder: { true })
    #expect((try? with.get()) == .media(from: .mp4, to: .mp3, seconds: 10))
}

@Test("documents become PDFs, and only Pages is a faithful rendering")
func planDocuments() throws {
    let word = try plan(source: .docx, ext: "pdf").get()
    #expect(word == .documentToPDF(from: .docx, faithful: false))
    #expect(word.isApproximate)          // must be disclosed to the user

    let pages = try plan(source: .pages, ext: "pdf").get()
    #expect(pages == .documentToPDF(from: .pages, faithful: true))
    #expect(!pages.isApproximate)
}

@Test("a PDF's text can be extracted")
func planPDFText() throws {
    #expect(try plan(source: .pdf, ext: "txt").get() == .pdfToText)
}

@Test("nonsense pairings are refused rather than attempted")
func planIncompatible() {
    #expect(plan(source: .mp4, ext: "png") == .failure(.incompatible(from: .mp4, to: .png)))
    #expect(plan(source: .docx, ext: "jpg") == .failure(.incompatible(from: .docx, to: .jpeg)))
    #expect(plan(source: .png, ext: "mp4") == .failure(.incompatible(from: .png, to: .mp4)))
}

// MARK: - Reading text out of pictures

/// Draw known words into an image, so what OCR should return is not in doubt.
private func makeTextImage(_ lines: [String], named name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConvertKitTests/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)

    let size = NSSize(width: 800, height: CGFloat(80 + lines.count * 60))
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    var y = size.height - 70
    for line in lines {
        (line as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: 34),
            .foregroundColor: NSColor.black,
        ])
        y -= 58
    }
    image.unlockFocus()

    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    return url
}

@Test("an image of words becomes those words")
func ocrReadsAnImage() throws {
    let url = try makeTextImage(["Total due 4200", "Due on Friday"], named: "note.png")
    let text = try TextRecognizer.text(inImageAt: url)
    #expect(text.contains("Total due 4200"))
    #expect(text.contains("Due on Friday"))
}

@Test("renaming a picture to .txt is planned as text recognition")
func planImageToText() throws {
    #expect(try plan(source: .png, ext: "txt").get() == .imageToText(from: .png))
    #expect(try plan(source: .heic, ext: "txt").get() == .imageToText(from: .heic))
}

@Test("a picture with no words in it says so rather than writing an empty file")
func ocrEmptyImage() throws {
    // A plain grey square: nothing to read.
    let url = try makeImage(.png, named: "blank.png")
    let text = try TextRecognizer.text(inImageAt: url)
    #expect(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test("a scanned PDF falls back to reading the pages")
func ocrScannedPDF() throws {
    // An image wrapped in a PDF has no text layer, which is what a scan is.
    let image = try makeTextImage(["Scanned heading", "Second line here"], named: "page.pdf")
    let wrap = try plan(source: .png, ext: "pdf").get()
    _ = try Converter(options: .init(keepOriginal: false)).run(wrap, on: image)

    let text = try TextRecognizer.text(inPDFAt: image)
    #expect(text.contains("Scanned heading"))
}

@Test("iWork documents are recognised, and count as a faithful conversion")
func planPagesIsFaithful() throws {
    let p = try plan(source: .pages, ext: "pdf").get()
    #expect(p == .documentToPDF(from: .pages, faithful: true))
    #expect(!p.isApproximate)
}

@Test("other applications' libraries are left alone entirely")
func watcherSkipsAppPackages() {
    let home = NSHomeDirectory()
    // Reading inside a Photos library raises a permission prompt and rewriting
    // anything in it corrupts the library.
    #expect(!RenameWatcher.isEligible(
        path: "\(home)/Pictures/Photos Library.photoslibrary/originals/4/IMG_1.jpeg"))
    #expect(!RenameWatcher.isEligible(
        path: "\(home)/Pictures/Photo Booth Library/Pictures/Movie.mov"))
    #expect(!RenameWatcher.isEligible(path: "/Applications/Some.app/Contents/Resources/icon.png"))
    #expect(!RenameWatcher.isEligible(path: "\(home)/Movies/Film.fcpbundle/x/clip.mov"))

    // A file whose own name resembles a package is still fair game.
    #expect(RenameWatcher.isEligible(path: "\(home)/Desktop/notes.app.png"))
    #expect(RenameWatcher.isEligible(path: "\(home)/Desktop/holiday.png"))
}
