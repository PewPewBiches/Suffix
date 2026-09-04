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
    /// Re-wrap or re-encode video, or pull the audio out of it.
    case media(from: FileFormat, to: FileFormat, seconds: Double)
    /// Lay a word-processing document out as a PDF.
    case documentToPDF(from: FileFormat, faithful: Bool)
    /// Pull the text out of a PDF, reading the pages if it has no text layer.
    case pdfToText
    /// Read the words out of a picture.
    case imageToText(from: FileFormat)

    /// Conversions we refuse, each with a reason worth showing the user.
    public enum Refusal: Error, Equatable, Sendable {
        case sameFormat(FileFormat)
        case unreadableSource
        case unwritableTarget(FileFormat)
        case unknownTargetExtension(String)
        /// Nothing sensible connects these two kinds of file.
        case incompatible(from: FileFormat, to: FileFormat)
        /// Possible, but needs a tool that isn't installed.
        case needsExternalTool(FileFormat, hint: String)
    }

    /// Work out the plan, or why there isn't one.
    public static func make(source: FileFormat?,
                            targetExtension: String,
                            pageCount: () -> Int,
                            mediaSeconds: () -> Double = { 0 },
                            hasMP3Encoder: () -> Bool = { ExternalEncoder.mp3Encoder() != nil })
        -> Result<ConversionPlan, Refusal>
    {
        guard let target = FileFormat.forExtension(targetExtension) else {
            return .failure(Refusal.unknownTargetExtension(targetExtension))
        }
        guard let source else { return .failure(Refusal.unreadableSource) }
        guard target.isWritable else { return .failure(Refusal.unwritableTarget(target)) }
        guard source != target else { return .failure(Refusal.sameFormat(source)) }
        if target.needsExternalEncoder && !hasMP3Encoder() {
            return .failure(Refusal.needsExternalTool(
                target, hint: "Install ffmpeg to convert to MP3 — try: brew install ffmpeg"))
        }

        switch (source.family, target.family) {
        case (.image, .image):
            return .success(ConversionPlan.reencode(from: source, to: target))
        case (.image, .pdf):
            return .success(ConversionPlan.imagesToPDF(from: source))
        case (.pdf, .image):
            let pages = pageCount()
            return .success(pages <= 1
                ? ConversionPlan.pdfToImage(to: target, pages: max(pages, 1))
                : ConversionPlan.pdfToImageArchive(to: target, pages: pages))
        case (.pdf, .document) where target == .txt:
            return .success(ConversionPlan.pdfToText)
        case (.image, .document) where target == .txt:
            return .success(ConversionPlan.imageToText(from: source))
        case (.document, .pdf):
            return .success(ConversionPlan.documentToPDF(
                from: source, faithful: source.isIWork))
        case (.video, .video), (.video, .audio), (.audio, .audio):
            return .success(ConversionPlan.media(from: source, to: target,
                                                 seconds: mediaSeconds()))
        default:
            return .failure(Refusal.incompatible(from: source, to: target))
        }
    }

    /// Conversions worth confirming before running, because they produce a lot
    /// of data or a differently-named file than the user typed.
    /// Jobs worth confirming: they take real time, or produce a differently
    /// named file than the one the user typed.
    public var needsConfirmation: Bool {
        switch self {
        case .pdfToImageArchive:
            return true
        case .media(_, _, let seconds):
            // Anything beyond a short clip stops feeling instant.
            return seconds > 60
        default:
            return false
        }
    }

    /// True when the result is a re-flow rather than a faithful rendering, and
    /// the user should be told before they send it to anyone.
    public var isApproximate: Bool {
        if case .documentToPDF(_, let faithful) = self { return !faithful }
        return false
    }

    public var summary: String {
        switch self {
        case .reencode(let f, let t):        return "\(f.displayName) → \(t.displayName)"
        case .imagesToPDF(let f):            return "\(f.displayName) → PDF"
        case .pdfToImage(let t, _):          return "PDF → \(t.displayName)"
        case .pdfToImageArchive(let t, let p): return "PDF (\(p) pages) → \(t.displayName) in a .zip"
        case .media(let f, let t, _):        return "\(f.displayName) → \(t.displayName)"
        case .documentToPDF(let f, _):       return "\(f.displayName) → PDF"
        case .pdfToText:                     return "PDF → Text"
        case .imageToText(let f):            return "\(f.displayName) → Text"
        }
    }
}
