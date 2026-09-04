import Foundation
import Vision
import PDFKit
import CoreGraphics
import AppKit

/// Reading text out of pictures, using the Vision framework macOS already ships.
///
/// This is the conversion nothing else on the machine offers as a rename:
/// `screenshot.png` → `screenshot.txt` gives you the words back. It also
/// rescues scanned PDFs, which contain pictures of text and so return nothing
/// from ordinary text extraction.
public enum TextRecognizer {
    /// Recognised text from one image, in reading order.
    public static func text(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        }
        return lines.joined(separator: "\n")
    }

    public static func text(inImageAt url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ConversionError.cannotRead(url) }
        return try text(in: image)
    }

    /// Text from a PDF: the embedded text layer where there is one, otherwise
    /// each page is rendered and read. A scanned document has no text layer,
    /// which is exactly when this matters.
    /// - Parameter progress: 0…1, since OCR of a long document is not instant.
    public static func text(inPDFAt url: URL,
                            progress: (@Sendable (Double) -> Void)? = nil) throws -> String {
        guard let document = PDFDocument(url: url) else { throw ConversionError.cannotRead(url) }

        if let embedded = document.string,
           embedded.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
            return embedded
        }

        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            // 2× gives Vision enough pixels to read body text reliably.
            let scale: CGFloat = 2
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

            if let rendered = context.makeImage() {
                pages.append(try text(in: rendered))
            }
            progress?(Double(index + 1) / Double(document.pageCount))
        }

        let joined = pages.joined(separator: "\n\n")
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.noTextFound
        }
        return joined
    }
}

/// Pages, Keynote and Numbers documents, exported by the app that made them.
///
/// A modern iWork file holds no PDF — only protobuf-encoded `.iwa` data and
/// JPEG previews — so the document has to be exported by its own application.
/// That is the only route that produces a faithful PDF.
public enum IWorkExport {
    /// Each iWork app, with the extension its documents must carry.
    ///
    /// The staged extension matters: AppleScript hands the file to the app by
    /// path, and Pages will not open a Keynote document just because it was
    /// renamed. Since the zip's contents cannot tell the three apart, each
    /// pairing is tried in turn.
    /// Apps are addressed by bundle identifier, never by name.
    ///
    /// `tell application "Pages"` resolves through Launch Services by display
    /// name, and Apple ships these apps with marketing display names ("Pages
    /// Creator Studio") that differ from the app itself — so matching on the
    /// visible name is unreliable in both directions.
    ///
    /// Both identifier forms are listed because Apple has used each: current
    /// versions are `com.apple.Pages`, older ones `com.apple.iWork.Pages`.
    private static let apps: [(ids: [String], ext: String)] = [
        (["com.apple.Pages",   "com.apple.iWork.Pages"],   "pages"),
        (["com.apple.Keynote", "com.apple.iWork.Keynote"], "key"),
        (["com.apple.Numbers", "com.apple.iWork.Numbers"], "numbers"),
    ]

    public static func toPDF(_ source: URL, destination: URL) throws {
        var firstError: String?

        for app in apps {
            guard let id = app.ids.first(where: isInstalled) else { continue }
            let wasRunning = isRunning(id)
            let staged = try stage(source, extension: app.ext)
            defer { try? FileManager.default.removeItem(at: staged) }

            do {
                try export(staged, to: destination, using: id)
                if FileManager.default.fileExists(atPath: destination.path) {
                    // Leave the desktop as we found it.
                    if !wasRunning { quit(id) }
                    return
                }
            } catch let error as ConversionError {
                if !wasRunning { quit(id) }
                if case .mediaExportFailed(let message) = error, firstError == nil {
                    // Report the first app's complaint, not the last: an app
                    // that lacks the terminology fails with a bare "syntax
                    // error" that buries the real reason.
                    firstError = message
                }
            }
        }
        throw ConversionError.iWorkExportFailed(
            firstError ?? "Pages, Keynote or Numbers must be installed to convert this")
    }

    /// Copy the document to a temporary file carrying `extension`, since the
    /// name Suffix was handed is by definition the wrong one.
    private static func stage(_ source: URL, extension ext: String) throws -> URL {
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(ext)")
        do { try FileManager.default.linkItem(at: source, to: staged) }
        catch { try FileManager.default.copyItem(at: source, to: staged) }
        return staged
    }

    private static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func quit(_ bundleID: String) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.terminate()
        }
    }

    private static func export(_ source: URL, to destination: URL, using bundleID: String) throws {
        // `application id` targets the bundle identifier, so a differently
        // named app cannot intercept the document.
        let script = """
        tell application id "\(bundleID)"
            set theDoc to open POSIX file "\(source.path)"
            export theDoc to POSIX file "\(destination.path)" as PDF
            close theDoc saving no
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConversionError.mediaExportFailed(
                String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "\(bundleID) refused the document")
        }
    }
}
