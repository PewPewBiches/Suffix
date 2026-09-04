// Generates the app icon. Run: swift Scripts/make-icon.swift <out.png>
//
// The mark is the dot and what follows it: a white period, then a selection-blue
// block standing for the highlighted extension. Two shapes, so it survives 16pt.
// See DESIGN.md.
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

// Ink ground.
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let body = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.145, green: 0.157, blue: 0.180, alpha: 1),
    CGColor(red: 0.055, green: 0.059, blue: 0.071, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(body, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
let sheen = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.11),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])
ctx.restoreGState()

// A selected extension: ".pdf" set in monospace, sitting inside a selection
// block. Abstract shapes read as a toggle switch; the letters say what it means.
let text = ".pdf" as NSString
let font = NSFont.monospacedSystemFont(ofSize: rect.width * 0.235, weight: .semibold)
let textSize = text.size(withAttributes: [.font: font])

let padX = rect.width * 0.055, padY = rect.width * 0.045
let block = CGRect(x: rect.midX - (textSize.width + padX * 2) / 2,
                   y: rect.midY - (textSize.height + padY * 2) / 2,
                   width: textSize.width + padX * 2,
                   height: textSize.height + padY * 2)

let layer = NSImage(size: NSSize(width: size, height: size))
layer.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
NSColor(srgbRed: 0.043, green: 0.384, blue: 0.965, alpha: 1).setFill()
NSBezierPath(roundedRect: block, xRadius: block.height * 0.27, yRadius: block.height * 0.27).fill()
text.draw(at: NSPoint(x: block.minX + padX, y: block.minY + padY),
          withAttributes: [.font: font, .foregroundColor: NSColor.white])
layer.unlockFocus()

if let cg = layer.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
}

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
