import AppKit
import ConvertKit
import Carbon.HIToolbox

/// A key combination, stored as the numbers Carbon needs and shown as the
/// symbols people recognise.
struct Shortcut: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32          // Carbon flags: cmdKey, optionKey, …

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_S),
                                    modifiers: UInt32(cmdKey | optionKey))

    /// e.g. "⌥⌘S"
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { text += "⌘" }
        return text + (Self.keyNames[Int(keyCode)] ?? "?")
    }

    /// Build from what an NSEvent reports, which uses different constants.
    init?(event: NSEvent) {
        var carbon: UInt32 = 0
        if event.modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option)  { carbon |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        // A shortcut with no modifier would swallow ordinary typing.
        guard carbon != 0 else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = carbon
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9", kVK_ANSI_0: "0",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
        kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/",
    ]
}

/// Registers one system-wide shortcut.
///
/// Carbon's hot-key API is the only way to claim a combination globally
/// without asking for accessibility permission, which is a heavy thing to
/// request for a convenience.
@MainActor
final class Hotkey {
    static let shared = Hotkey()

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private static let signature = OSType(0x53464658)   // 'SFFX'

    /// Claim `shortcut`, replacing whatever was registered before.
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if id.signature == Hotkey.signature {
                Task { @MainActor in Hotkey.shared.action?() }
            }
            return noErr
        }, 1, &eventType, nil, &handler)

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         id, GetApplicationEventTarget(), 0, &reference)
        if status != noErr {
            // Almost always because something else already owns the
            // combination; the settings pane says so rather than failing mute.
            Log.write("could not claim \(shortcut.display) — status \(status)")
        }
    }

    var isRegistered: Bool { reference != nil }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
