// Generates the app icon. Run: swift Scripts/make-icon.swift <out.png>
//
// Graphite rather than a brand colour, so it sits quietly among Apple's own
// utilities instead of announcing itself.
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

let inset = size * 0.094
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.2237
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
let space = CGColorSpaceCreateDeviceRGB()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let body = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.267, green: 0.286, blue: 0.310, alpha: 1),
    CGColor(red: 0.141, green: 0.153, blue: 0.169, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(body, start: CGPoint(x: 0, y: rect.maxY),
                       end: CGPoint(x: 0, y: rect.minY), options: [])

let sheen = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.13),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: rect.maxY),
                       end: CGPoint(x: 0, y: rect.midY), options: [])
ctx.restoreGState()

// The conversion glyph, in white on graphite. An earlier version drew a dot
// and a bar for the "suffix" idea; at icon sizes it read as a redaction mark
// rather than a filename, so this says what the app does instead.
let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.50, weight: .regular)
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
