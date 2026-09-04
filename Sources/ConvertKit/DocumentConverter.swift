import Foundation
import AppKit
import PDFKit

/// Word-processing documents to PDF, and PDFs to plain text.
///
/// Uses `NSAttributedString`, which reads Word, RTF, OpenDocument, HTML and
/// text natively. It is **not** Word's layout engine: text and basic formatting
/// survive, but tables, columns, headers and footers, and precise pagination do
/// not. Callers are expected to say so rather than let people discover it in a
/// document they have already sent.
@MainActor
public struct DocumentConverter {
    public init() {}

    /// Formats whose PDF output is a faithful rendering rather than a re-flow.
    public static func isFaithful(_ format: FileFormat) -> Bool {
        // A Pages file carries a PDF made by Pages itself, so it matches
        // exactly. Everything else is re-laid-out by AppKit.
        format == .pages
    }

    public func toPDF(_ url: URL, from source: FileFormat, destination: URL) throws {
        if source == .pages {
            try Self.extractPagesPreview(url, to: destination)
            return
        }

        guard let text = try? NSAttributedString(
            url: url,
            options: [.documentType: Self.documentType(for: source)],
            documentAttributes: nil), text.length > 0
        else { throw ConversionError.cannotRead(url) }

        let page = NSSize(width: 612, height: 792)      // US Letter, in points
        let margin: CGFloat = 54

        let view = NSTextView(frame: NSRect(
            origin: .zero,
            size: NSSize(width: page.width - margin * 2, height: page.height - margin * 2)))
        view.textStorage?.setAttributedString(text)

        let info = NSPrintInfo(dictionary: [:])
        info.paperSize = page
        info.topMargin = margin; info.bottomMargin = margin
        info.leftMargin = margin; info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw ConversionError.encodingFailed(.pdf) }
    }

    /// Pull the readable text out of a PDF.
    public func toText(_ url: URL, destination: URL) throws {
        guard let document = PDFDocument(url: url) else { throw ConversionError.cannotRead(url) }
        guard let text = document.string, !text.isEmpty else {
            throw ConversionError.noTextFound
        }
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    private static func documentType(for format: FileFormat) -> NSAttributedString.DocumentType {
        switch format {
        case .docx: return .officeOpenXML
        case .doc:  return .docFormat
        case .odt:  return .openDocument
        case .rtf:  return .rtf
        case .html: return .html
        default:    return .plain
        }
    }

    /// A .pages file is a zip that usually carries a PDF preview written by
    /// Pages itself — perfect fidelity, and no need to drive the app.
    static func extractPagesPreview(_ url: URL, to destination: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", "-j", url.path, "QuickLook/Preview.pdf", "-d", staging.path]
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        let preview = staging.appendingPathComponent("Preview.pdf")
        guard FileManager.default.fileExists(atPath: preview.path) else {
            throw ConversionError.noPagesPreview
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: preview, to: destination)
    }
}
