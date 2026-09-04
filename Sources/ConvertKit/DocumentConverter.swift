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
        // An iWork document is exported by the app that made it, so it matches
        // exactly. Everything else is re-laid-out by AppKit.
        format.isIWork
    }

    public func toPDF(_ url: URL, from source: FileFormat, destination: URL) throws {
        if source.isIWork {
            try IWorkExport.toPDF(url, from: source, destination: destination)
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

    /// Pull the readable text out of a PDF, reading the pages with OCR when
    /// there is no text layer — which is the case for anything scanned.
    public func toText(_ url: URL, destination: URL,
                       progress: (@Sendable (Double) -> Void)? = nil) throws {
        let text = try TextRecognizer.text(inPDFAt: url, progress: progress)
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    /// Read the words out of a picture.
    public func toText(image url: URL, destination: URL) throws {
        let text = try TextRecognizer.text(inImageAt: url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
}
