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
                    StatusDot(state: state)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(permission.title)
                            .font(.body).fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text(statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    // `.notNeeded` counts as satisfied, so a machine without
                    // Pages never sees an "Optional" badge it cannot act on.
                    if !state.isSatisfied {
                        Text(permission.isRequired ? "Needed" : "Optional")
                            .font(.caption2).fontWeight(.medium)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(permission.isRequired ? Color.orange.opacity(0.18)
                                                              : Color.secondary.opacity(0.14),
                                        in: Capsule())
                            .foregroundStyle(permission.isRequired ? .orange : .secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(permission.why)
                        .fixedSize(horizontal: false, vertical: true)

                    Label {
                        Text(permission.limit)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    .foregroundStyle(.secondary)

                    if !state.isSatisfied {
                        Button(permission.isAskable ? "Ask macOS now" : permission.settingsLabel,
                               action: act)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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

private struct StatusDot: View {
    let state: Permission.State

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(tint)
            .frame(width: 18)
    }

    private var symbol: String {
        switch state {
        case .granted:   return "checkmark.circle.fill"
        case .denied:    return "xmark.circle.fill"
        case .notAsked:  return "circle.dashed"
        case .notNeeded: return "minus.circle"
        }
    }

    private var tint: Color {
        switch state {
        case .granted:   return Style.accent
        case .denied:    return .orange
        default:         return .secondary
        }
    }
}

/// The same list, plus the two facts that are true whatever macOS decides.
struct PermissionAssurance: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Row(icon: "wifi.slash",
                text: "Suffix has no networking in it. Nothing is uploaded, and there is nothing to upload it with.")
            Row(icon: "chevron.left.forwardslash.chevron.right",
                text: "The source is public. Every one of these claims is checkable rather than promised.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private struct Row: View {
        let icon: String
        let text: String
        var body: some View {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: icon).frame(width: 15)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
