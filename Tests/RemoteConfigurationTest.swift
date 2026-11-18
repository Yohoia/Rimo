import AppKit
import Carbon.HIToolbox
import Foundation

@main
struct RemoteConfigurationTest {
    static func main() throws {
        let returnKey = KeyboardShortcut(option: KeyboardShortcut.navigationKeys[0], flags: [])
        let command = SystemShortcut(id: UUID(), name: "Example (with parentheses)")
        let globalAction = RemoteAction.keyboard(returnKey)
        let sceneAction = RemoteAction.shortcut(command)

        var configuration = RemoteConfiguration()
        configuration.global[.playPause] = globalAction
        configuration.scenes = [AppSceneMapping(id: "sample.player", name: "Player", buttons: configuration.global)]
        configuration.scenes[0].buttons[.playPause] = sceneAction

        precondition(configuration.action(for: .playPause, in: "sample.player") == globalAction)
        configuration.automatic = true
        precondition(configuration.action(for: .playPause, in: "sample.player") == sceneAction)
        precondition(configuration.action(for: .playPause, in: "sample.other") == globalAction)
        precondition(configuration.action(for: .playPause, in: nil) == globalAction)

        configuration.scenes[0].buttons.setEnabled(false, for: .playPause)
        precondition(configuration.action(for: .playPause, in: "sample.player") == nil)
        precondition(configuration.action(for: .playPause, in: "sample.other") == globalAction)

        let decoded = try JSONDecoder().decode(RemoteConfiguration.self, from: JSONEncoder().encode(configuration))
        precondition(decoded == configuration)
        configuration.scenes[0].enabled = false
        precondition(configuration.action(for: .playPause, in: "sample.player") == globalAction)
        try verifyPresets(globalAction: globalAction, otherAction: sceneAction)
        try verifyTriggerMappings(single: globalAction, additional: sceneAction)
        try verifyExpandedActions()
        try verifyApplicationTargets()
        verifyKeyboardCatalog()
        try verifyScrollMode()
        try verifyOtherActions()
        verifyRemotePresses()
        print("Scenes, mapping persistence, scroll mode, HID de-duplication and trigger recognition passed.")
    }

    static func verifyScrollMode() throws {
        let toggle = RemoteAction.system(.toggleScrollMode)
        let directions: [(RemoteButton, ScrollAction.Direction)] = [
            (.up, .up), (.down, .down), (.left, .left), (.right, .right)
        ]
        var mode = RemoteScrollMode()
        precondition(directions.allSatisfy { mode.scroll(for: $0.0) == nil })
        mode.toggle()
        for (button, direction) in directions {
            precondition(mode.scroll(for: button)?.direction == direction && !toggle.isAssignable(to: button))
        }
        let ordinaryButtons = RemoteButton.allCases.filter { button in !directions.contains { $0.0 == button } }
        precondition(ordinaryButtons.allSatisfy { mode.scroll(for: $0) == nil && toggle.isAssignable(to: $0) })
        mode.toggle()
        precondition(!mode.enabled && mode.scroll(for: .down) == nil)

        // Old files may contain a direction-key binding. Keep it editable but never dispatch it.
        let appID = "sample.reader"
        let legacyScroll = RemoteAction.scroll(.init(direction: .left))
        var configuration = RemoteConfiguration()
        var sceneButtons = ButtonMappings()
        for trigger in RemoteTrigger.allCases {
            configuration.global[.up, trigger] = toggle
            sceneButtons[.down, trigger] = toggle
        }
        configuration.global[.left] = legacyScroll
        configuration.global[.mute, .hold] = toggle
        configuration.scenes = [.init(id: appID, name: "Reader", buttons: sceneButtons)]
        configuration.automatic = true
        let restored = try JSONDecoder().decode(RemoteConfiguration.self, from: JSONEncoder().encode(configuration))
        for trigger in RemoteTrigger.allCases {
            precondition(restored.global[.up, trigger] == toggle)
            precondition(restored.action(for: .up, trigger: trigger, in: nil) == nil)
            precondition(restored.action(for: .down, trigger: trigger, in: appID) == nil)
        }
        precondition(restored.action(for: .mute, trigger: .hold, in: nil) == toggle)
        precondition(restored.action(for: .left, in: nil) == legacyScroll)
    }

    static func verifyOtherActions() throws {
        let categories = SystemAction.windowActions + SystemAction.systemActions + SystemAction.editingActions + SystemAction.otherActions
        precondition(Set(categories).count == categories.count)
        precondition(Set(categories) == Set(SystemAction.allCases))
        var signatures: Set<String> = []
        for action in SystemAction.otherActions {
            if let key = action.shortcut {
                precondition(signatures.insert("\(key.keyCode):\(key.modifiers)").inserted)
            } else { precondition(action == .toggleScrollMode) }
        }
        for action in categories {
            let value = RemoteAction.system(action)
            let restored = try JSONDecoder().decode(RemoteAction.self, from: JSONEncoder().encode(value))
            precondition(restored == value)
        }
        precondition(SystemAction.copy.shortcut?.keyCode == UInt16(kVK_ANSI_C))
        precondition(SystemAction.copy.shortcut?.modifiers == UInt64(NSEvent.ModifierFlags.command.rawValue))
        precondition(SystemAction.redo.shortcut?.modifiers == UInt64(NSEvent.ModifierFlags([.command, .shift]).rawValue))
    }

    static func verifyKeyboardCatalog() {
        let keys = KeyboardShortcut.navigationKeys
        let grouped = KeyboardShortcut.keyGroups.flatMap(\.keys)
        precondition(Set(keys.map(\.id)).count == keys.count)
        precondition(Set(grouped.map(\.id)).count == grouped.count)
        precondition(Set(grouped.map(\.id)) == Set(keys.map(\.id)))
        for code in [kVK_Function, kVK_Command, kVK_RightCommand, kVK_Option, kVK_RightOption,
                     kVK_Control, kVK_RightControl, kVK_Shift, kVK_RightShift, kVK_CapsLock,
                     kVK_Return, kVK_Escape, kVK_ForwardDelete] {
            let option = keys.first { $0.id == UInt16(code) }!
            let shortcut = KeyboardShortcut(option: option, flags: [])
            precondition(shortcut.keyCode == UInt16(code) && shortcut.modifiers == 0)
            if KeyboardShortcut.modifierFlag(for: UInt16(code)) != nil {
                precondition(shortcut.outputModifierCodes.isEmpty)
            }
        }
        precondition(!keys.contains { [UInt16(kVK_ANSI_A), UInt16(kVK_ANSI_0), UInt16(kVK_ANSI_Keypad0), UInt16(kVK_F1), UInt16(kVK_F20)].contains($0.id) })
    }

    static func verifyPresets(globalAction: RemoteAction, otherAction: RemoteAction) throws {
        var config = RemoteConfiguration()
        let app = "sample.reader"
        config.global[.playPause] = globalAction
        config.global[.volumeUp] = globalAction
        config.global.setEnabled(false, for: .volumeUp)
        config.global[.up] = otherAction
        config.global.setEnabled(false, for: .up)
        config.apply(.reading, to: app, name: "Reader")

        precondition(!config.automatic)
        precondition(config.action(for: .up, in: app) == nil)
        config.automatic = true

        let expected: [(ScenePreset, [RemoteButton: Int])] = [
            (.presentation, [.left: kVK_LeftArrow, .right: kVK_RightArrow, .back: kVK_Escape]),
            (.reading, [.up: kVK_PageUp, .down: kVK_PageDown]),
            (.webVideo, [.select: kVK_ANSI_K, .left: kVK_ANSI_J, .right: kVK_ANSI_L, .down: kVK_ANSI_F])
        ]
        for (preset, keys) in expected {
            let id = preset.rawValue
            config.apply(preset, to: id, name: id)
            for button in RemoteButton.allCases {
                if let keyCode = keys[button] {
                    guard case .keyboard(let action) = config.action(for: button, in: id) else {
                        preconditionFailure("Missing preset action for \(button)")
                    }
                    precondition(action.keyCode == keyCode && action.modifiers == 0)
                } else if RemoteButton.a2540Buttons.contains(button) {
                    precondition(config.action(for: button, in: id) != nil)
                    precondition(config.scene(for: id)?.inherits(button) == false)
                }
            }
        }
        precondition(config.action(for: .playPause, in: app) == .media(.playPause))
        precondition(config.action(for: .volumeUp, in: app) == .media(.volumeUp))
        config.global[.playPause] = otherAction
        precondition(config.scenes[0].resolved(global: config.global)[.playPause] == .media(.playPause))
        precondition(config.action(for: .playPause, in: app) == .media(.playPause))

        let global = config.global
        config.scenes[0].edit(.playPause, global: global) { $0.setEnabled(false, for: .playPause) }
        precondition(config.scenes[0].buttons[.playPause] == .media(.playPause))
        precondition(config.action(for: .playPause, in: app) == nil)
        config.scenes[0].followGlobal(.playPause)
        precondition(config.action(for: .playPause, in: app) == otherAction)
        config.scenes[0].edit(.playPause, global: global) { $0[.playPause] = nil }
        precondition(config.action(for: .playPause, in: app) == nil)

        let legacyID = "sample.legacy"
        var oldButtons = ButtonMappings()
        oldButtons[.playPause] = globalAction
        oldButtons.setEnabled(false, for: .playPause)
        oldButtons[.left] = otherAction
        oldButtons.setEnabled(false, for: .left)
        config.scenes.append(.init(id: legacyID, name: "Existing", enabled: false, buttons: oldButtons))
        config.apply(.presentation, to: legacyID, name: "Renamed")
        let legacy = config.scenes.last!
        precondition(!legacy.enabled && legacy.name == "Existing" && !legacy.canFollowGlobal)
        precondition(legacy.buttons[.playPause] == .media(.playPause) && legacy.buttons.isEnabled(.playPause))
        precondition(legacy.buttons[.left] != otherAction && legacy.buttons.isEnabled(.left))
        precondition(!legacy.inherits(.volumeUp))

        let saved = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(RemoteConfiguration.self, from: saved)
        precondition(restored == config)
        precondition(restored.scene(for: app)?.inherits(.volumeUp) == false)
        precondition(restored.action(for: .playPause, in: app) == nil)

        var partial = RemoteConfiguration()
        var oldPreset = AppSceneMapping(id: "partial", name: "Partial", buttons: ButtonMappings(), overrides: [])
        oldPreset.edit(.up, global: partial.global) { $0[.up] = globalAction }
        oldPreset.edit(.back, global: partial.global) { $0[.back] = nil }
        partial.scenes = [oldPreset]
        partial.completeSceneMappings()
        precondition(partial.scenes[0].buttons[.up] == globalAction)
        precondition(partial.scenes[0].buttons[.back] == nil)
        precondition(partial.scenes[0].buttons[.volumeUp] == .media(.volumeUp))
        let completed = partial
        partial.completeSceneMappings()
        precondition(partial == completed)
    }

    static func verifyTriggerMappings(single: RemoteAction, additional: RemoteAction) throws {
        var config = RemoteConfiguration(automatic: true)
        config.global[.left] = single
        config.global[.left, .doublePress] = additional
        config.global[.left, .hold] = additional
        config.apply(.presentation, to: "app", name: "App")
        precondition(config.action(for: .left, in: "app") != single)
        precondition(config.action(for: .left, trigger: .doublePress, in: "app") == additional)
        let global = config.global
        config.scenes[0].edit(.left, trigger: .doublePress, global: global) {
            $0[.left, .doublePress] = single
            $0.setEnabled(false, for: .left, trigger: .doublePress)
        }
        precondition(config.action(for: .left, trigger: .doublePress, in: "app") == nil)
        precondition(config.action(for: .left, trigger: .hold, in: "app") == additional)
        let saved = try JSONDecoder().decode(RemoteConfiguration.self, from: JSONEncoder().encode(config))
        precondition(saved == config)
        config.scenes[0].followGlobal(.left, trigger: .doublePress)
        precondition(config.action(for: .left, trigger: .doublePress, in: "app") == additional)
        precondition(config.action(for: .left, trigger: .doublePress, in: "another-app") == additional)

        let legacy = Data(#"{"global":{"actions":{},"disabled":["left"]},"scenes":[],"automatic":false}"#.utf8)
        let restored = try JSONDecoder().decode(RemoteConfiguration.self, from: legacy)
        precondition(!restored.global.isEnabled(.left) && restored.global.isEnabled(.left, trigger: .hold))
    }

    static func verifyExpandedActions() throws {
        let legacy = Data(#"{"keyCode":36,"modifiers":0,"label":"↩"}"#.utf8)
        let oldKey = try JSONDecoder().decode(KeyboardShortcut.self, from: legacy)
        precondition(oldKey.holdsUntilRelease == nil && oldKey.modifierKeyCodes == nil)
        var held = KeyboardShortcut(option: .init(id: UInt16(kVK_ANSI_C), title: "C"), flags: [.command, .option])
        held.holdsUntilRelease = true
        held.modifierKeyCodes = [UInt16(kVK_RightCommand), UInt16(kVK_RightOption)]
        precondition(held.outputModifierCodes == [UInt16(kVK_RightOption), UInt16(kVK_RightCommand)])
        let changed = held.updating(flags: .command)
        precondition(changed.holdsUntilRelease == true)
        precondition(changed.outputModifierCodes == [UInt16(kVK_RightCommand)])
        let actions: [RemoteAction] = [
            .keyboard(held), .mouse(.doubleClick), .scroll(.init(direction: .left, amount: 120)),
            .media(.nextTrack), .system(.lockScreen), .openApp(.init(bundleIdentifier: "com.apple.TextEdit", name: "文本编辑")),
            .text(.init(value: "你好 👩‍💻\n/model", appendReturn: true))
        ]
        for action in actions {
            var config = RemoteConfiguration(automatic: true)
            config.global[.select, .hold] = action
            config.apply(.reading, to: "reader", name: "Reader")
            let restored = try JSONDecoder().decode(RemoteConfiguration.self, from: JSONEncoder().encode(config))
            precondition(restored == config)
            precondition(restored.action(for: .select, trigger: .hold, in: "reader") == action)
            restored.scenes.forEach { precondition($0.inherits(.select, trigger: .hold)) }
        }
        precondition(ScrollAction(direction: .down, amount: Int.max).deltas.vertical == -600)
        precondition(ScrollAction(direction: .up, amount: -1).deltas.vertical == 10)
        precondition(ScrollAction(direction: .left, amount: 80).deltas.horizontal == 80)
        precondition(ScrollAction(direction: .right, amount: 80).deltas.horizontal == -80)
        precondition(SystemAction.missionControl.shortcut?.keyCode == UInt16(kVK_UpArrow))
        print("Expanded actions: persistence, scene inheritance, legacy keys, held output and scroll bounds passed.")
    }

    static func verifyApplicationTargets() throws {
        let old = Data(#"{"bundleIdentifier":"com.apple.TextEdit","name":"文本编辑"}"#.utf8)
        let legacy = try JSONDecoder().decode(AppTarget.self, from: old)
        precondition(legacy.path == nil && legacy.installedURL?.lastPathComponent == "TextEdit.app")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Example App.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "test.rimo.application", "CFBundleName": "Example App", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let selected = AppTarget.at(app)
        precondition(selected?.bundleIdentifier == info["CFBundleIdentifier"])
        precondition(selected?.installedURL?.path == app.path)
        precondition(AppTarget.at(contents) == nil)

        let action = RemoteAction.openApp(selected!)
        let restored = try JSONDecoder().decode(RemoteAction.self, from: JSONEncoder().encode(action))
        precondition(restored == action)
    }

    static func verifyRemotePresses() {
        var held = RemoteButtonState()
        let first = RemoteButtonState.Source(device: 1, cookie: 2)
        let duplicate = RemoteButtonState.Source(device: 2, cookie: 2)
        precondition(held.update(.left, pressed: true, from: first) == .pressed)
        precondition(held.update(.left, pressed: true, from: duplicate) == nil)
        precondition(held.update(.left, pressed: true, from: first) == nil)
        precondition(held.update(.left, pressed: false, from: first) == nil)
        precondition(held.update(.left, pressed: false, from: duplicate) == .released)
        precondition(held.update(.left, pressed: false, from: duplicate) == nil)

        var immediate = RemotePressSequence(recognizesDouble: false, recognizesHold: false)
        precondition(immediate.receive(.pressed, at: 0) == [.single] && immediate.deadline == nil)
        precondition(immediate.receive(.released, at: 0.18).isEmpty)

        var sequence = RemotePressSequence(recognizesDouble: true, recognizesHold: true)
        precondition(sequence.receive(.pressed, at: 1).isEmpty)
        precondition(sequence.receive(.released, at: 1.06).isEmpty)
        precondition(sequence.advance(to: 1.25) == nil)
        precondition(sequence.advance(to: 1.33) == .single && sequence.isIdle)
        precondition(sequence.receive(.pressed, at: 2).isEmpty)
        precondition(sequence.receive(.released, at: 2.05).isEmpty)
        precondition(sequence.receive(.pressed, at: 2.15).isEmpty)
        precondition(sequence.receive(.released, at: 2.23) == [.doublePress])
        precondition(sequence.advance(to: 2.8) == nil && sequence.isIdle)
        precondition(sequence.receive(.pressed, at: 3).isEmpty)
        precondition(sequence.advance(to: 3.49) == nil)
        precondition(sequence.advance(to: 3.50) == .hold)
        precondition(sequence.advance(to: 3.80) == nil)
        precondition(sequence.receive(.released, at: 3.85).isEmpty)

        // A late timer cannot classify a separated second tap as a double.
        precondition(sequence.receive(.pressed, at: 4).isEmpty)
        precondition(sequence.receive(.released, at: 4.04).isEmpty)
        precondition(sequence.receive(.pressed, at: 4.34) == [.single])
        precondition(sequence.receive(.released, at: 4.90) == [.hold])
        precondition(sequence.isIdle)

        var onlyHold = RemotePressSequence(recognizesDouble: false, recognizesHold: true)
        precondition(onlyHold.receive(.pressed, at: 0).isEmpty)
        precondition(onlyHold.receive(.released, at: 0.18) == [.single])
    }
}
