// Generates the app icon. Run: swift Scripts/make-icon.swift <out.png>
//
// The mark is the app's name, drawn the way the app draws everything else: a
// white period, then an S in Krungthep with the six colours living inside it.
// Suffix is what comes after the dot, so the icon is a dot and what comes
// after it.
//
// The dot is white rather than part of the rainbow. At 16pt a coloured dot
// dissolves into the letter beside it and the mark becomes one blob; white
// keeps two shapes, which is the whole requirement for an icon that small.
// See DESIGN.md.
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rainbow = [
    CGColor(red: 0.38, green: 0.73, blue: 0.27, alpha: 1),
    CGColor(red: 0.99, green: 0.72, blue: 0.15, alpha: 1),
    CGColor(red: 0.96, green: 0.51, blue: 0.12, alpha: 1),
    CGColor(red: 0.88, green: 0.23, blue: 0.24, alpha: 1),
    CGColor(red: 0.59, green: 0.24, blue: 0.59, alpha: 1),
    CGColor(red: 0.00, green: 0.62, blue: 0.86, alpha: 1),
]

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

let inset = size * 0.094
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.2237

ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

// Ink ground, very slightly lit from above so it does not read as a hole.
let body = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    CGColor(red: 0.125, green: 0.129, blue: 0.145, alpha: 1),
    CGColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(body, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])

/// The S as a path, so the colours can live inside the letter rather than
/// behind it.
func letterS(height fraction: Double, offsetX: Double) -> CGPath {
    let font = CTFontCreateWithName("Krungthep" as CFString, 100, nil)
    var characters = Array("S".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1)
    guard let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { exit(1) }
    let bounds = path.boundingBoxOfPath
    let scale = (rect.height * fraction) / bounds.height
    var transform = CGAffineTransform(
        translationX: rect.midX + offsetX - bounds.midX * scale,
        y: rect.midY - bounds.midY * scale
    ).scaledBy(x: scale, y: scale)
    return path.copy(using: &transform)!
}

let s = letterS(height: 0.50, offsetX: rect.width * 0.08)
let sBounds = s.boundingBoxOfPath

// Six bands, sized to the letter so all six survive being clipped by it.
ctx.saveGState()
ctx.addPath(s); ctx.clip()
let band = sBounds.height / 6
for i in 0..<6 {
    ctx.setFillColor(rainbow[i])
    ctx.fill(CGRect(x: sBounds.minX, y: sBounds.maxY - band * Double(i + 1),
                    width: sBounds.width, height: band + 1))
}
ctx.restoreGState()

// The dot: square, because System 7 had no round corners this small, and
// sitting on the letter's baseline.
let dot = sBounds.height * 0.30
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fill(CGRect(x: sBounds.minX - dot - rect.width * 0.055, y: sBounds.minY,
                width: dot, height: dot))

ctx.restoreGState()

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
