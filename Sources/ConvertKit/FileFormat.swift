import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A file format Rename understands, identified by *content* rather than by name.
public enum FileFormat: String, Sendable, CaseIterable {
    case png, jpeg, tiff, gif, bmp, heic, webp, pdf

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
        }
    }

    public var preferredExtension: String { extensions[0] }

    /// Human-facing name used in notifications.
    public var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .pdf:  return "PDF"
        case .heic: return "HEIC"
        case .webp: return "WebP"
        default:    return rawValue.uppercased()
        }
    }

    public var utType: UTType {
        switch self {
        case .png:  return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .gif:  return .gif
        case .bmp:  return .bmp
        case .heic: return .heic
        case .webp: return .webP
        case .pdf:  return .pdf
        }
    }

    /// Can we *write* this format? (WebP is readable on macOS but not writable
    /// through ImageIO, so it is deliberately excluded here.)
    public var isWritable: Bool { self != .webp }

    /// True when this format stores raster pixels (everything except PDF).
    public var isRaster: Bool { self != .pdf }

    /// Resolve a user-typed extension to the format they meant.
    public static func forExtension(_ ext: String) -> FileFormat? {
        let needle = ext.lowercased()
        return allCases.first { $0.extensions.contains(needle) }
    }

    /// Identify a file by sniffing its bytes. The filename is never consulted,
    /// which is the whole point: the name is what the user just changed.
    public static func detect(at url: URL) -> FileFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 16) else { return nil }
        try? handle.close()
        if head.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }   // %PDF

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(src) as String?,
              let type = UTType(uti) else { return nil }
        return allCases.first { $0.isRaster && type.conforms(to: $0.utType) }
    }
}
