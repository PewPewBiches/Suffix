import Foundation

/// What converting `source` into `target` would actually entail.
///
/// Deciding this *before* doing any work lets the UI warn about the expensive
/// cases (a 500-page PDF) instead of silently chewing through them.
public enum ConversionPlan: Equatable, Sendable {
    /// Re-encode one raster image as another raster format.
    case reencode(from: FileFormat, to: FileFormat)
    /// Wrap one or more images into a single PDF.
    case imagesToPDF(from: FileFormat)
    /// Render a single-page PDF to one image file.
    case pdfToImage(to: FileFormat, pages: Int)
    /// Render a multi-page PDF to many images, delivered as a .zip.
    case pdfToImageArchive(to: FileFormat, pages: Int)

    /// Conversions we refuse, each with a reason worth showing the user.
    public enum Refusal: Error, Equatable, Sendable {
        case sameFormat(FileFormat)
        case unreadableSource
        case unwritableTarget(FileFormat)
        case unknownTargetExtension(String)
    }

    /// Work out the plan, or why there isn't one.
    public static func make(source: FileFormat?, targetExtension: String, pageCount: () -> Int)
        -> Result<ConversionPlan, Refusal>
    {
        guard let target = FileFormat.forExtension(targetExtension) else {
            return .failure(Refusal.unknownTargetExtension(targetExtension))
        }
        guard let source else { return .failure(Refusal.unreadableSource) }
        guard target.isWritable else { return .failure(Refusal.unwritableTarget(target)) }
        guard source != target else { return .failure(Refusal.sameFormat(source)) }

        switch (source.isRaster, target.isRaster) {
        case (true, true):
            return .success(ConversionPlan.reencode(from: source, to: target))
        case (true, false):
            return .success(ConversionPlan.imagesToPDF(from: source))
        case (false, true):
            let pages = pageCount()
            return .success(pages <= 1
                ? ConversionPlan.pdfToImage(to: target, pages: max(pages, 1))
                : ConversionPlan.pdfToImageArchive(to: target, pages: pages))
        case (false, false):
            return .failure(Refusal.sameFormat(source))
        }
    }

    /// Conversions worth confirming before running, because they produce a lot
    /// of data or a differently-named file than the user typed.
    public var needsConfirmation: Bool {
        if case .pdfToImageArchive = self { return true }
        return false
    }

    public var summary: String {
        switch self {
        case .reencode(let f, let t):        return "\(f.displayName) → \(t.displayName)"
        case .imagesToPDF(let f):            return "\(f.displayName) → PDF"
        case .pdfToImage(let t, _):          return "PDF → \(t.displayName)"
        case .pdfToImageArchive(let t, let p): return "PDF (\(p) pages) → \(t.displayName) in a .zip"
        }
    }
}
