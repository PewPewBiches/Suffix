// Draws the disk-image window background. Run: swift Scripts/make-dmg-background.swift <out.png> <scale>
//
// The installer is the first thing anyone sees, before the app has drawn a
// single pixel of its own, so it is built from the same parts: the dither
// desktop, Krungthep for chrome, the six-colour rule, a 1px-framed note.
// The icon positions here have to match the ones make-dmg.sh gives Finder.
import AppKit

let W = 640.0, H = 448.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "bg.png"
let scale = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 1.0

let rainbow = [
    CGColor(red: 0.38, green: 0.73, blue: 0.27, alpha: 1),
    CGColor(red: 0.99, green: 0.72, blue: 0.15, alpha: 1),
    CGColor(red: 0.96, green: 0.51, blue: 0.12, alpha: 1),
    CGColor(red: 0.88, green: 0.23, blue: 0.24, alpha: 1),
    CGColor(red: 0.59, green: 0.24, blue: 0.59, alpha: 1),
    CGColor(red: 0.00, green: 0.62, blue: 0.86, alpha: 1),
]
let black = CGColor(gray: 0.05, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)
let dim   = CGColor(gray: 0.32, alpha: 1)

guard let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: scale, y: scale)

/// Everything below is written with y measured from the top, the way the
/// Finder coordinates in make-dmg.sh are, so the two stay readable together.
func rect(_ x: Double, _ yTop: Double, _ w: Double, _ h: Double) -> CGRect {
    CGRect(x: x, y: H - yTop - h, width: w, height: h)
}
func fill(_ r: CGRect, _ c: CGColor) { ctx.setFillColor(c); ctx.fill(r) }
func frame(_ r: CGRect, _ w: Double = 1) {
    ctx.setStrokeColor(black); ctx.setLineWidth(w); ctx.stroke(r.insetBy(dx: w/2, dy: w/2))
}
func text(_ s: String, _ face: String, _ size: Double, _ colour: CGColor,
          x: Double, yTop: Double, centred: Bool = false) {
    let font = CTFontCreateWithName(face as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: colour)!]))
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: centred ? x - w/2 : x, y: H - yTop - size)
    CTLineDraw(line, ctx)
}

// ── the 50% dither desktop ───────────────────────────────────────────
fill(CGRect(x: 0, y: 0, width: W, height: H), CGColor(gray: 0.604, alpha: 1))
ctx.setFillColor(CGColor(gray: 0.557, alpha: 1))
var y = 0.0
while y < H {
    var x = y.truncatingRemainder(dividingBy: 4) < 2 ? 0.0 : 2.0
    while x < W { ctx.fill(CGRect(x: x, y: y, width: 2, height: 2)); x += 4 }
    y += 2
}

// ── the window this all sits in ──────────────────────────────────────
let panel = rect(24, 22, W - 48, H - 46)
fill(panel, CGColor(gray: 0.87, alpha: 1))
frame(panel)

// title bar, pinstriped, with the name punched through
let bar = rect(24, 22, W - 48, 22)
fill(bar, white)
ctx.setFillColor(black)
var ty = 26.0
while ty < 42 { ctx.fill(rect(25, ty, W - 50, 1)); ty += 3 }
ctx.fill(rect(24, 43, W - 48, 1))
let titleBox = rect(W/2 - 44, 24, 88, 18)
fill(titleBox, CGColor(gray: 0.87, alpha: 1))
text("suffix", "Krungthep", 12, black, x: W/2, yTop: 28, centred: true)
// close box
fill(rect(34, 27, 12, 12), white); frame(rect(34, 27, 12, 12))

// ── headline and the six-colour rule ─────────────────────────────────
text("install suffix", "Krungthep", 27, black, x: 48, yTop: 62)
let ruleW = (W - 96) / 6
for i in 0..<6 { fill(rect(48 + ruleW * Double(i), 100, ruleW, 4), rainbow[i]) }

text("Drag it onto the Applications folder. That is the install.",
     "Geneva", 13, black, x: 48, yTop: 116)

// ── the arrow between the two icon slots ─────────────────────────────
// Icon centres live at x=170 and x=470, y=214 — see make-dmg.sh.
let ax = 258.0, aw = 124.0, ay = 206.0
fill(rect(ax, ay, aw - 22, 8), black)
let tip = CGMutablePath()
tip.move(to: CGPoint(x: ax + aw, y: H - ay - 4))
tip.addLine(to: CGPoint(x: ax + aw - 26, y: H - ay + 14))
tip.addLine(to: CGPoint(x: ax + aw - 26, y: H - ay - 22))
tip.closeSubpath()
ctx.addPath(tip); ctx.setFillColor(black); ctx.fillPath()

// ── the one thing that surprises people, said before it happens ──────
let note = rect(48, 292, W - 96, 116)
fill(note, white); frame(note)
let tag = rect(48, 284, 152, 17)
fill(tag, black)
text("macOS WILL BLOCK IT", "Krungthep", 10, white, x: 56, yTop: 287)

text("The app is unsigned, so Gatekeeper stops it once. You only do this once.",
     "Geneva", 12, black, x: 64, yTop: 308)
text("1.  Drag suffix across, then open it. Let macOS refuse.", "Geneva", 12, black, x: 64, yTop: 334)
text("2.  System Settings → Privacy & Security.", "Geneva", 12, black, x: 64, yTop: 354)
text("3.  Scroll to the line about suffix, click Open Anyway.", "Geneva", 12, black, x: 64, yTop: 374)

// ── and the promise, small, centred at the foot ──────────────────────
text("Free · MIT · no account · nothing is uploaded · macOS 14+",
     "Geneva", 11, dim, x: W/2, yTop: 420, centred: true)

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) at \(Int(scale))x")
