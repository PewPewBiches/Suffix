import SwiftUI
import AppKit
import ConvertKit

/// Renders the app's surfaces to PNGs so the design can be reviewed without a
/// screen recording permission or a human at the keyboard.
///
/// Run with `REname --render-previews <dir>`; the app renders and exits.
@MainActor
enum DesignPreview {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-previews"), i + 1 < args.count else {
            return false
        }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = AppModel.shared
        for (name, view) in surfaces(model: model) {
            for scheme in [ColorScheme.light, .dark] {
                let tagged = AnyView(
                    view
                        .environment(\.colorScheme, scheme)
                        .background(scheme == .dark ? Color(white: 0.11) : Color(white: 0.96))
                )
                write(tagged, to: dir.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        return true
    }

    private static func surfaces(model: AppModel) -> [(String, AnyView)] {
        var out: [(String, AnyView)] = []
        for step in 0..<4 {
            out.append(("setup-\(step)",
                        AnyView(OnboardingView(model: model, startStep: step, finish: {})
                                    .frame(width: 520, height: 460))))
        }
        out.append(("settings", AnyView(SettingsView(model: model).frame(width: 460))))
        out.append(("notice", AnyView(
            NoticeView(notice: Notice(title: "Converted",
                                      from: "invoice.png",
                                      to: "invoice.pdf",
                                      detail: "invoice.png kept alongside",
                                      thumbnail: nil,
                                      undo: {}, reveal: {}),
                       dismiss: {})
                .padding(20))))
        return out
    }

    private static func write(_ view: AnyView, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write("could not render \(url.lastPathComponent)\n".data(using: .utf8)!)
            return
        }
        try? png.write(to: url)
        print("rendered \(url.lastPathComponent)")
    }
}
