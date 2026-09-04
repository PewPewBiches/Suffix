// Generates the app icon. Run: swift Scripts/make-icon.swift <out.png>
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

// macOS icons sit on a rounded square inset from the canvas edge.
let inset = size * 0.094
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.2237
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.098, green: 0.573, blue: 0.502, alpha: 1),   // lighter top
    CGColor(red: 0.035, green: 0.353, blue: 0.310, alpha: 1),   // deeper base
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: rect.maxY),
                       end: CGPoint(x: 0, y: rect.minY), options: [])
ctx.restoreGState()

// A soft top sheen. Drawn as a gradient rather than a filled ellipse, whose
// hard edge read as a seam across the middle of the icon.
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let sheen = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen,
                       start: CGPoint(x: 0, y: rect.maxY),
                       end: CGPoint(x: 0, y: rect.midY), options: [])
ctx.restoreGState()

// The mark: the same circular-arrows glyph the menu bar uses, so the app is
// recognisable from either place.
let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.52, weight: .medium)
if let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                        accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let target = NSImage(size: NSSize(width: size, height: size))
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = symbol.size
    let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2)
    NSColor.white.set()
    symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    NSRect(origin: origin, size: s).fill(using: .sourceAtop)
    target.unlockFocus()

    if let cg = target.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
    }
}

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
