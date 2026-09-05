import SwiftUI
import AppKit

/// The permission checklist, shown during setup and again in Settings.
///
/// Every row says three things in order: what macOS is being asked for, what
/// Suffix does with it, and what it cannot do with it. The third one is the
/// part that is usually left out, and it is the only part that makes the first
/// two worth reading.
struct PermissionList: View {
    @ObservedObject var monitor: PermissionMonitor
    /// Setup shows one row at a time expanded; Settings shows them collapsed.
    var startExpanded: Permission?

    @State private var expanded: Permission?

    init(monitor: PermissionMonitor, startExpanded: Permission? = nil) {
        self.monitor = monitor
        self.startExpanded = startExpanded
        _expanded = State(initialValue: startExpanded)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Permission.allCases) { permission in
                PermissionRow(
                    permission: permission,
                    state: monitor.states[permission] ?? .notAsked,
                    isExpanded: expanded == permission,
                    toggle: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expanded = (expanded == permission) ? nil : permission
                        }
                    },
                    act: {
                        permission.ask()
                        // The prompt and the settings pane both land in another
                        // process; measure again shortly after rather than
                        // assuming the answer.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(600))
                            monitor.refresh()
                        }
                    })
            }
        }
        .onAppear { monitor.startWatching() }
        .onDisappear { monitor.stopWatching() }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let state: Permission.State
    let isExpanded: Bool
    let toggle: () -> Void
    let act: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    StatusMark(state: state)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(permission.title)
                            .font(S7.chrome(13))
                            .foregroundStyle(S7.black)
                        Text(statusLine)
                            .font(S7.read(11.5))
                            .foregroundStyle(S7.dim)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    // `.notNeeded` counts as satisfied, so a Mac without Pages
                    // never sees an "Optional" badge it cannot act on.
                    if !state.isSatisfied {
                        Text(permission.isRequired ? "NEEDED" : "OPTIONAL")
                            .font(S7.chrome(9))
                            .foregroundStyle(permission.isRequired ? S7.white : S7.black)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(permission.isRequired ? S7.black : S7.white)
                            .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
                    }

                    // The disclosure triangle System 7 actually used.
                    Triangle()
                        .fill(S7.black)
                        .frame(width: 7, height: 8)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    Rectangle().fill(S7.black).frame(height: 1)

                    Text(permission.why)
                        .font(S7.read(12.5))
                        .foregroundStyle(S7.black)
                        .fixedSize(horizontal: false, vertical: true)

                    // The limit gets the selection block, because "what this
                    // does not allow" is the thing being asserted.
                    VStack(alignment: .leading, spacing: 5) {
                        Text("WHAT IT DOES NOT ALLOW")
                            .font(S7.chrome(9))
                            .foregroundStyle(S7.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(S7.black)
                        Text(permission.limit)
                            .font(S7.read(12.5))
                            .foregroundStyle(S7.black)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !state.isSatisfied {
                        if let steps = permission.settingsSteps {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(steps.indices, id: \.self) { i in
                                    HStack(alignment: .top, spacing: 7) {
                                        Text("\(i + 1).")
                                            .font(S7.chrome(11))
                                            .foregroundStyle(S7.black)
                                            .frame(width: 15, alignment: .leading)
                                        Text(steps[i])
                                            .font(S7.read(12))
                                            .foregroundStyle(S7.black)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                        Button(permission.isAskable ? "Ask macOS now" : permission.settingsLabel,
                               action: act)
                            .buttonStyle(.s7)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 11)
                .padding(.top, 2)
            }
        }
        .background(S7.white)
        .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
    }

    private var statusLine: String {
        switch state {
        case .granted:              return "Allowed"
        case .denied:               return permission.isRequired
                                         ? "Not allowed — Suffix cannot see your files"
                                         : "Not allowed"
        case .notAsked:             return "macOS will ask the first time it is needed"
        case .notNeeded(let why):   return why
        }
    }
}

/// A filled square in one of the six colours, rather than a traffic light.
/// System 7 put colour on objects, not on text.
private struct StatusMark: View {
    let state: Permission.State

    var body: some View {
        ZStack {
            Rectangle().fill(fill).frame(width: 13, height: 13)
                .overlay(Rectangle().strokeBorder(S7.black, lineWidth: 1))
            if case .granted = state {
                Path { path in
                    path.move(to: CGPoint(x: 2.5, y: 6.5))
                    path.addLine(to: CGPoint(x: 5.5, y: 9.5))
                    path.addLine(to: CGPoint(x: 10.5, y: 3))
                }
                .stroke(S7.black, style: StrokeStyle(lineWidth: 2, lineCap: .square))
                .frame(width: 13, height: 13)
            }
        }
        .frame(width: 16)
    }

    private var fill: Color {
        switch state {
        case .granted:   return S7.green
        case .denied:    return S7.red
        case .notAsked:  return S7.white
        case .notNeeded: return S7.faint.opacity(0.4)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The same list, plus the two facts that are true whatever macOS decides.
struct PermissionAssurance: View {
    var body: some View {
        S7Note(tag: "Whatever you grant") {
            VStack(alignment: .leading, spacing: 6) {
                Row("Suffix has no networking in it. Nothing is uploaded, and there is nothing in the app capable of uploading it.")
                Row("The source is public. Every one of these claims is checkable rather than promised.")
            }
        }
    }

    private struct Row: View {
        let text: String
        init(_ text: String) { self.text = text }
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(S7.black).frame(width: 4, height: 4).padding(.top, 6)
                Text(text)
                    .font(S7.read(12))
                    .foregroundStyle(S7.black)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
