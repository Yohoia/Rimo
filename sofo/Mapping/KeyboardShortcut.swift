import AppKit
import Carbon.HIToolbox
import CoreGraphics

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt64
    let label: String
    var holdsUntilRelease: Bool? = nil
    var modifierKeyCodes: [UInt16]? = nil

    var title: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        let symbols: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "Fn")
        ]
        return symbols.compactMap { flags.contains($0.0) ? $0.1 : nil }.joined() + label
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control, .function])
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
        var result = self
        result = Self(code: keyCode, label: label, modifiers: UInt64(flags.rawValue))
        result.holdsUntilRelease = holdsUntilRelease
        result.modifierKeyCodes = modifierKeyCodes?.filter { code in
            Self.modifierFlag(for: code).map { flags.contains($0) } ?? false
        }
        return result
    }

    static let navigationKeys = [
        kVK_Return, kVK_Space, kVK_Escape, kVK_Tab, kVK_Delete, kVK_ForwardDelete,
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ANSI_KeypadEnter,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_Command, kVK_RightCommand, kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl, kVK_Shift, kVK_RightShift, kVK_Function
    ].map { Option(id: UInt16($0), title: specialKeys[$0]!) }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Escape: "Esc",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Tab: "⇥", kVK_Space: "空格",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_Command: "左 Command", kVK_RightCommand: "右 Command",
        kVK_Option: "左 Option", kVK_RightOption: "右 Option",
        kVK_Control: "左 Control", kVK_RightControl: "右 Control",
        kVK_Shift: "左 Shift", kVK_RightShift: "右 Shift", kVK_Function: "Fn"
    ]

    static func modifierFlag(for code: UInt16) -> NSEvent.ModifierFlags? {
        switch Int(code) {
        case kVK_Command, kVK_RightCommand: .command
        case kVK_Option, kVK_RightOption: .option
        case kVK_Control, kVK_RightControl: .control
        case kVK_Shift, kVK_RightShift: .shift
        case kVK_Function: .function
        default: nil
        }
    }

    var outputModifierCodes: [UInt16] {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        let defaults = [kVK_Control, kVK_Option, kVK_Shift, kVK_Command, kVK_Function].map(UInt16.init)
        return defaults.compactMap { code in
            guard let flag = Self.modifierFlag(for: code), flags.contains(flag) else { return nil }
            return modifierKeyCodes?.first(where: { Self.modifierFlag(for: $0) == flag }) ?? code
        }.filter { $0 != keyCode }
    }

    @discardableResult
    func post() -> Bool {
        guard post(pressed: true) else { return false }
        return post(pressed: false)
    }

    @discardableResult
    func post(pressed: Bool) -> Bool {
        guard CGPreflightPostEventAccess(), let source = CGEventSource(stateID: .privateState) else { return false }
        let codes = outputModifierCodes
        let allFlags = CGEventFlags(rawValue: modifiers)
            .union(CGEventFlags(rawValue: UInt64(Self.modifierFlag(for: keyCode)?.rawValue ?? 0)))
        let output = pressed ? codes + [keyCode] : [keyCode] + codes.reversed()
        for code in output {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: pressed) else { return false }
            event.flags = pressed ? allFlags : []
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}
