import SwiftUI
import AppKit

/// The website's world, in the app.
///
/// The site is System 7 and the app was stock SwiftUI, which made them two
/// products. This file is the shared vocabulary: the six-colour palette, the
/// pinstriped title bar, 1px black frames with a hard shadow, and a black
/// selection block as the only emphasis device. See DESIGN.md.
///
/// **On type.** Chicago is not on macOS any more — it went with the Classic
/// environment. Krungthep is: a Thai face whose Latin set is squared, heavy
/// and flat-terminalled, which is Chicago's job exactly. It ships with the
/// system, so the app matches the website without redistributing somebody
/// else's font. Krungthep carries chrome, Geneva carries reading, Monaco
/// carries filenames — the last two are period correct and still shipping.
enum S7 {
    // MARK: palette

    /// Ink. Inverts in dark mode, exactly as the site's night palette does.
    static let black = Color(light: Color(white: 0.04), dark: Color(red: 0.91, green: 0.91, blue: 0.90))
    /// The fill a control sits on.
    static let white = Color(light: .white, dark: Color(red: 0.10, green: 0.10, blue: 0.11))
    /// Window body.
    static let paper = Color(light: Color(red: 0.87, green: 0.87, blue: 0.87),
                             dark:  Color(red: 0.14, green: 0.14, blue: 0.15))
    static let dim   = Color(light: Color(white: 0.33), dark: Color(white: 0.65))
    static let faint = Color(light: Color(white: 0.48), dark: Color(white: 0.49))
    static let shadow = Color(light: .black.opacity(0.34), dark: .black.opacity(0.6))

    /// The 1977 six-colour logo, used as this design's whole palette.
    static let green  = Color(red: 0.38, green: 0.73, blue: 0.27)
    static let yellow = Color(red: 0.99, green: 0.72, blue: 0.15)
    static let orange = Color(red: 0.96, green: 0.51, blue: 0.12)
    static let red    = Color(red: 0.88, green: 0.23, blue: 0.24)
    static let purple = Color(red: 0.59, green: 0.24, blue: 0.59)
    static let blue   = Color(red: 0.00, green: 0.62, blue: 0.86)
    static let rainbow: [Color] = [green, yellow, orange, red, purple, blue]

    // MARK: type

    /// Chrome: titles, buttons, labels. Krungthep stands in for Chicago.
    ///
    /// No weight is ever requested. These faces ship with one each, and asking
    /// SwiftUI for a bold that does not exist drops the whole family back to
    /// the system font — which is how this first looked like stock SwiftUI in
    /// a costume. DESIGN.md says the same thing from the other end: the
    /// selection block is the only emphasis device, so there is no bold to
    /// want.
    static func chrome(_ size: CGFloat) -> Font {
        .custom(chromeFamily, size: size)
    }

    /// Falls back rather than assuming. Krungthep has shipped with macOS for
    /// twenty years, but a font can be disabled in Font Book, and losing the
    /// family silently means losing every label in the app.
    private static let chromeFamily: String = {
        let families = NSFontManager.shared.availableFontFamilies
        for name in ["Krungthep", "Silom", "Geneva"] where families.contains(name) {
            return name
        }
        return "Geneva"
    }()
    /// Reading text.
    static func read(_ size: CGFloat) -> Font { .custom("Geneva", size: size) }
    /// Filenames, extensions, anything the machine wrote.
    static func data(_ size: CGFloat) -> Font { .custom("Monaco", size: size) }
}

// MARK: - the window

/// A System 7 window: 1px frame, pinstriped title bar, hard shadow.
struct S7Window<Content: View>: View {
    var title: String
    /// Nil hides the close box — the setup window has its own way out.
    var close: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            S7TitleBar(title: title, close: close)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(S7.paper)
        }
        .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
        .background(
            Rectangle().fill(S7.shadow).offset(x: 2, y: 2)
        )
    }
}

struct S7TitleBar: View {
    var title: String
    var close: (() -> Void)?

    var body: some View {
        ZStack {
            Pinstripe()
            HStack(spacing: 8) {
                if let close {
                    Button(action: close) {
                        Rectangle()
                            .fill(S7.white)
                            .frame(width: 11, height: 11)
                            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                } else {
                    Spacer().frame(width: 11)
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(S7.chrome(12))
                    .foregroundStyle(S7.black)
                    .padding(.horizontal, 8)
                    .background(S7.paper)          // the title punches a hole in the stripes
                    .fixedSize()
                Spacer(minLength: 0)
                Spacer().frame(width: 11)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 21)
        .overlay(alignment: .bottom) { Rectangle().fill(S7.black).frame(height: 1) }
    }
}

/// The 1px-on, 2px-off horizontal rule that made a System 7 title bar.
private struct Pinstripe: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(S7.white))
            var y: CGFloat = 2
            while y < size.height - 1 {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(S7.black))
                y += 3
            }
        }
        .drawingGroup()
    }
}

/// The six-colour rule, which is the site's one piece of decoration.
struct S7Rule: View {
    var height: CGFloat = 3
    var body: some View {
        HStack(spacing: 0) {
            ForEach(S7.rainbow.indices, id: \.self) { i in
                Rectangle().fill(S7.rainbow[i])
            }
        }
        .frame(height: height)
    }
}

// MARK: - controls

/// Square, 1px, hard-shadowed. Inverts when pressed, the way System 7 did.
struct S7ButtonStyle: ButtonStyle {
    var isDefault = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(S7.chrome(12))
            .foregroundStyle(configuration.isPressed ? S7.white : S7.black)
            .padding(.horizontal, 15)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? S7.black : S7.white)
            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
            // The default button wore a second, heavier ring.
            .overlay {
                if isDefault {
                    Rectangle().strokeBorder(S7.black, lineWidth: 2).padding(-4)
                }
            }
            .background(Rectangle().fill(S7.shadow).offset(x: 1.5, y: 1.5))
            .opacity(enabled ? 1 : 0.4)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == S7ButtonStyle {
    static var s7: S7ButtonStyle { S7ButtonStyle() }
    static var s7Default: S7ButtonStyle { S7ButtonStyle(isDefault: true) }
}

/// A square check box with a hand-drawn tick.
struct S7CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ZStack {
                    Rectangle().fill(S7.white).frame(width: 13, height: 13)
                        .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                    if configuration.isOn {
                        Path { path in
                            path.move(to: CGPoint(x: 2.5, y: 6.5))
                            path.addLine(to: CGPoint(x: 5.5, y: 9.5))
                            path.addLine(to: CGPoint(x: 10.5, y: 3))
                        }
                        .stroke(S7.black, style: StrokeStyle(lineWidth: 2, lineCap: .square))
                        .frame(width: 13, height: 13)
                    }
                }
                configuration.label
                    .font(S7.read(13))
                    .foregroundStyle(S7.black)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The selection block: black fill, white text, monospace. The app's one
/// emphasis device, and it always means "this is the thing being acted on".
struct S7Selection: View {
    let text: String
    var size: CGFloat = 12

    var body: some View {
        Text(text)
            .font(S7.data(size))
            .foregroundStyle(S7.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(S7.black)
    }
}

/// `invoice.png → invoice` + a selected `.pdf`
struct S7RenameChip: View {
    let from: String
    let to: String
    var size: CGFloat = 12

    private var parts: (stem: String, ext: String) {
        guard let dot = to.lastIndex(of: ".") else { return (to, "") }
        return (String(to[to.startIndex..<dot]), String(to[dot...]))
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(from).font(S7.data(size)).foregroundStyle(S7.dim)
            Text("→").font(S7.chrome(size)).foregroundStyle(S7.faint)
            HStack(spacing: 0) {
                Text(parts.stem).font(S7.data(size)).foregroundStyle(S7.black)
                S7Selection(text: parts.ext, size: size)
            }
        }
        .lineLimit(1)
    }
}

/// A framed area for secondary text — the site's `.note` box.
struct S7Note<Content: View>: View {
    var tag: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let tag {
                Text(tag)
                    .font(S7.chrome(10))
                    .foregroundStyle(S7.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(S7.black)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(S7.white)
        .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
    }
}

/// The 50% dither that was the System 7 desktop.
struct S7Desktop: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(light: Color(white: 0.60), dark: Color(white: 0.16))))
            let dot = Color(light: Color(white: 0.56), dark: Color(white: 0.13))
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = (y.truncatingRemainder(dividingBy: 4) < 2) ? 0 : 2
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: 2, height: 2)), with: .color(dot))
                    x += 4
                }
                y += 2
            }
        }
        .drawingGroup()
        .ignoresSafeArea()
    }
}

/// A window with no macOS chrome, because the app draws its own.
///
/// A borderless `NSWindow` refuses to become key by default, which would
/// leave every button and text field in it dead. Overriding that is the whole
/// reason this subclass exists.
final class S7WindowHost: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init(size: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: size),
                  styleMask: [.borderless, .fullSizeContentView],
                  backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        center()
    }
}
