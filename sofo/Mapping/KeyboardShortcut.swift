import AppKit
import Carbon.HIToolbox
import CoreGraphics

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt64
    let label: String

    var title: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        let symbols: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")
        ]
        return symbols.compactMap { flags.contains($0.0) ? $0.1 : nil }.joined() + label
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        // Resolve the base key without shortcut modifiers so ⌥ combinations display their physical key.
        let characters = event.characters(byApplyingModifiers: [])
        guard let label = Self.specialKeys[Int(event.keyCode)] ?? characters?.uppercased(),
              !label.isEmpty, label.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        self.keyCode = event.keyCode
        self.modifiers = UInt64(modifiers.rawValue)
        self.label = label
    }

    struct Option: Identifiable {
        let id: UInt16
        let title: String
    }

    private init(code: UInt16, label: String, modifiers: UInt64) {
        keyCode = code
        self.label = label
        self.modifiers = modifiers
    }

    init(option: Option, flags: NSEvent.ModifierFlags) {
        self.init(code: option.id, label: option.title, modifiers: UInt64(flags.rawValue))
    }

    func updating(flags: NSEvent.ModifierFlags) -> Self {
        Self(code: keyCode, label: label, modifiers: UInt64(flags.rawValue))
    }

    static let navigationKeys = [
        kVK_Return, kVK_Space, kVK_Escape, kVK_Tab, kVK_Delete, kVK_ForwardDelete,
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ANSI_KeypadEnter,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ].map { Option(id: UInt16($0), title: specialKeys[$0]!) }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Escape: "Esc",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Tab: "⇥", kVK_Space: "空格",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    @discardableResult
    func post() -> Bool {
        guard CGPreflightPostEventAccess(),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }

        let flags = CGEventFlags(rawValue: modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
