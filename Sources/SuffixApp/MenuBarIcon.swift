import AppKit

/// The menu bar mark: the same dot-and-S as the app icon, drawn flat.
///
/// It was an SF Symbol — a blue circular-arrows glyph left over from before
/// the app had a design of its own. The menu bar wants a *template* image:
/// one colour plus alpha, which macOS then tints to match the bar in light
/// mode, dark mode, and while the menu is open. So the six colours cannot
/// come along; the shape has to carry it alone, which it does, because the
/// shape is a dot and a letter.
@MainActor
enum MenuBarIcon {
    // Drawn on every progress tick, so the results are kept. Main-actor
    // isolated because that is the only thread that ever asks for one.
    private static var cache: [String: NSImage] = [:]

    /// - Parameter progress: nil when idle. Otherwise 0…1, and the letter
    ///   fills from the baseline up — a conversion visibly running rather
    ///   than an icon that looks identical whether or not anything is
    ///   happening.
    /// - Parameter enabled: a paused app draws the same mark, hollow.
    static func image(progress: Double? = nil, enabled: Bool = true) -> NSImage {
        // Quantised, because this is redrawn on every progress update and a
        // menu bar cannot show more than a few steps anyway.
        let step = progress.map { Int(($0 * 8).rounded()) }
        let key = "\(step.map(String.init) ?? "-")-\(enabled)"
        if let hit = cache[key] { return hit }

        let size = NSSize(width: 17, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let box = CGRect(origin: .zero, size: size)

            let letter = letterPath(in: box)
            let bounds = letter.boundingBoxOfPath
            let dotSide = bounds.height * 0.30
            let dot = CGRect(x: bounds.minX - dotSide - 2.0, y: bounds.minY,
                             width: dotSide, height: dotSide)

            // fill(_ rect:) would reset the current path and throw the
            // letter away, so both shapes go in as paths and fill together.
            ctx.setFillColor(NSColor.black.cgColor)

            if let progress {
                // Ghost the whole mark, then draw the filled part solid.
                ctx.saveGState()
                ctx.setAlpha(0.3)
                ctx.addPath(letter); ctx.addRect(dot); ctx.fillPath()
                ctx.restoreGState()

                ctx.saveGState()
                ctx.clip(to: CGRect(x: box.minX, y: box.minY,
                                    width: box.width,
                                    height: box.height * max(0, min(1, progress))))
                ctx.addPath(letter); ctx.addRect(dot); ctx.fillPath()
                ctx.restoreGState()
            } else if enabled {
                ctx.addPath(letter); ctx.addRect(dot); ctx.fillPath()
            } else {
                // Paused: the outline only, so the difference is visible at a
                // glance without a second glyph to learn.
                ctx.saveGState()
                ctx.setAlpha(0.45)
                ctx.addPath(letter); ctx.addRect(dot); ctx.fillPath()
                ctx.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }

    private static func letterPath(in box: CGRect) -> CGPath {
        let font = CTFontCreateWithName("Krungthep" as CFString, 100, nil)
        var characters = Array("S".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1)
        guard let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
            return CGPath(rect: box, transform: nil)
        }
        let bounds = path.boundingBoxOfPath
        let scale = (box.height * 0.74) / bounds.height
        var transform = CGAffineTransform(
            translationX: box.midX + 2.0 - bounds.midX * scale,
            y: box.midY - bounds.midY * scale
        ).scaledBy(x: scale, y: scale)
        return path.copy(using: &transform) ?? CGPath(rect: box, transform: nil)
    }
}
