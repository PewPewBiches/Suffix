import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Broad kinds of file, which decide *how* a conversion is done.
public enum Family: Sendable {
    case image, pdf, video, audio, document
}

/// A file format Suffix understands, identified by *content* rather than by name.
public enum FileFormat: String, Sendable, CaseIterable {
    // Images
    case png, jpeg, tiff, gif, bmp, heic, webp
    // Documents that render to pages
    case pdf
    // Video containers
    case mov, mp4, m4v
    // Audio
    case m4a, mp3, wav, aiff
    // Word-processing documents
    case docx, doc, rtf, odt, html, txt, pages

    public var family: Family {
        switch self {
        case .png, .jpeg, .tiff, .gif, .bmp, .heic, .webp: return .image
        case .pdf:                                          return .pdf
        case .mov, .mp4, .m4v:                              return .video
        case .m4a, .mp3, .wav, .aiff:                       return .audio
        case .docx, .doc, .rtf, .odt, .html, .txt, .pages:  return .document
        }
    }

    /// Extensions a user might type to ask for this format.
    public var extensions: [String] {
        switch self {
        case .png:  return ["png"]
        case .jpeg: return ["jpg", "jpeg", "jpe"]
        case .tiff: return ["tif", "tiff"]
        case .gif:  return ["gif"]
        case .bmp:  return ["bmp"]
        case .heic: return ["heic", "heif"]
        case .webp: return ["webp"]
        case .pdf:  return ["pdf"]
        case .mov:  return ["mov", "qt"]
        case .mp4:  return ["mp4"]
        case .m4v:  return ["m4v"]
        case .m4a:  return ["m4a"]
        case .mp3:  return ["mp3"]
        case .wav:  return ["wav", "wave"]
        case .aiff: return ["aif", "aiff"]
        case .docx: return ["docx"]
        case .doc:  return ["doc"]
        case .rtf:  return ["rtf"]
        case .odt:  return ["odt"]
        case .html: return ["html", "htm"]
        case .txt:  return ["txt", "text"]
        case .pages: return ["pages"]
        }
    }

    public var preferredExtension: String { extensions[0] }

    public var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .pdf:  return "PDF"
        case .heic: return "HEIC"
        case .webp: return "WebP"
        case .docx: return "Word"
        case .doc:  return "Word"
        case .odt:  return "OpenDocument"
        case .rtf:  return "RTF"
        case .html: return "HTML"
        case .txt:  return "Text"
        case .pages: return "Pages"
        default:    return rawValue.uppercased()
        }
    }

    /// The UTType, where one is meaningful for encoding.
    public var utType: UTType? {
        switch self {
        case .png:  return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .gif:  return .gif
        case .bmp:  return .bmp
        case .heic: return .heic
        case .webp: return .webP
        case .pdf:  return .pdf
        case .mov:  return .quickTimeMovie
        case .mp4:  return .mpeg4Movie
        case .m4v:  return UTType("com.apple.m4v-video")
        case .m4a:  return UTType("com.apple.m4a-audio")
        case .wav:  return .wav
        case .aiff: return .aiff
        default:    return nil
        }
    }

    /// Can Suffix *produce* this format?
    ///
    /// WebP is readable but has no macOS encoder. MP3 is listed as writable
    /// but needs a helper that may not be installed — planning checks that
    /// separately so the refusal can say what to install.
    public var isWritable: Bool {
        switch self {
        case .webp, .docx, .doc, .odt, .html, .pages, .rtf: return false
        default: return true
        }
    }

    /// True for formats macOS itself cannot encode, needing an outside tool.
    public var needsExternalEncoder: Bool { self == .mp3 }

    public static func forExtension(_ ext: String) -> FileFormat? {
        let needle = ext.lowercased()
        return allCases.first { $0.extensions.contains(needle) }
    }

    /// Identify a file by sniffing its bytes. The filename is never consulted,
    /// which is the whole point: the name is what the user just changed.
    public static func detect(at url: URL) -> FileFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 512) else { return nil }
        try? handle.close()
        guard head.count >= 12 else { return nil }
        let bytes = [UInt8](head)

        func ascii(_ range: Range<Int>) -> String {
            String(bytes: bytes[range], encoding: .ascii) ?? ""
        }

        // PDF
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }

        // ISO base media (mp4 / mov / m4a / m4v): "ftyp" at offset 4, then a brand.
        if bytes.count >= 12, ascii(4..<8) == "ftyp" {
            let brand = ascii(8..<12)
            switch brand.prefix(3) {
            case "qt ": return .mov
            case "M4A": return .m4a
            case "M4V": return .m4v
            default:    return .mp4
            }
        }
        // Older QuickTime files lead with an atom rather than ftyp.
        if bytes.count >= 8, ["moov", "mdat", "wide", "free", "skip"].contains(ascii(4..<8)) {
            return .mov
        }

        // RIFF/WAVE and AIFF
        if ascii(0..<4) == "RIFF", ascii(8..<12) == "WAVE" { return .wav }
        if ascii(0..<4) == "FORM", ["AIFF", "AIFC"].contains(ascii(8..<12)) { return .aiff }

        // MP3: an ID3 tag, or a raw frame sync.
        if ascii(0..<3) == "ID3" { return .mp3 }
        if bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0 { return .mp3 }

        // Zip-based documents. The member names distinguish them.
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return zipFlavour(at: url)
        }

        // Legacy Word (OLE compound file)
        if bytes.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) { return .doc }

        // RTF
        if ascii(0..<5) == "{\\rtf" { return .rtf }

        // Images, via the system's own decoders.
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let uti = CGImageSourceGetType(src) as String?,
           let type = UTType(uti),
           let match = allCases.first(where: {
               $0.family == .image && $0.utType.map(type.conforms(to:)) == true
           }) {
            return match
        }

        // HTML, then plain text, judged on content.
        let prefix = String(decoding: head, as: UTF8.self).lowercased()
        if prefix.contains("<html") || prefix.contains("<!doctype html") { return .html }
        if String(data: head, encoding: .utf8) != nil { return .txt }

        return nil
    }

    /// Zip containers all start alike; the entries inside say what they are.
    private static func zipFlavour(at url: URL) -> FileFormat? {
        guard let listing = try? Process.output(
            "/usr/bin/unzip", ["-l", "-qq", url.path]) else { return nil }
        if listing.contains("word/document.xml") { return .docx }
        if listing.contains("mimetypeapplication/vnd.oasis") || listing.contains("content.xml") { return .odt }
        // Modern iWork documents carry protobuf .iwa files; older ones a
        // single Index.zip. Neither contains a PDF, despite what the previous
        // version of this code assumed.
        if listing.contains("Index/Document.iwa") || listing.contains("Index.zip")
            || listing.contains("QuickLook/Preview.pdf") { return .pages }
        return nil
    }
}

extension Process {
    /// Run a tool and return its standard output.
    static func output(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
