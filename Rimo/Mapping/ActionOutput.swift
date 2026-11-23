import AppKit
import CoreGraphics

/// Emits one configured action. Shortcut execution remains owned by RimoModel.
@MainActor
enum ActionOutput {
    static func perform(_ action: RemoteAction) throws {
        if case .openApp(let app) = action {
            guard let url = app.installedURL else {
                throw OutputError.message("找不到「\(app.name)」，请重新选择应用程序。")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
            return
        }
        if case .system(.activateSiri) = action {
            let workspace = NSWorkspace.shared
            // macOS 27 shows Siri through "Siri AI" (com.apple.campo); the older
            // bundles still launch there but stay invisible, so try it first.
            for bundleID in ["com.apple.campo", "com.apple.siri.launcher", "com.apple.Siri"] {
                if let url = workspace.urlForApplication(withBundleIdentifier: bundleID), workspace.open(url) { return }
            }
            throw OutputError.message("无法打开 Siri。请确认已在 macOS 系统设置中启用 Siri。")
        }
        guard CGPreflightPostEventAccess() else {
            throw OutputError.message("请在设备设置中允许辅助功能，再执行映射。")
        }
        switch action {
        case .keyboard(let key):
            guard key.post() else { throw OutputError.message("无法发送快捷键。") }
        case .mouse(let click):
            let button: CGMouseButton = click == .right ? .right : click == .middle ? .center : .left
            let down: CGEventType = click == .right ? .rightMouseDown : click == .middle ? .otherMouseDown : .leftMouseDown
            let up: CGEventType = click == .right ? .rightMouseUp : click == .middle ? .otherMouseUp : .leftMouseUp
            let point = CGEvent(source: nil)?.location ?? .zero
            for count in 1...(click == .doubleClick ? 2 : 1) {
                for type in [down, up] {
                    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
                    event?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
                    event?.post(tap: .cghidEventTap)
                }
            }
        case .scroll(let scroll):
            let delta = scroll.deltas
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: delta.vertical, wheel2: delta.horizontal, wheel3: 0)?.post(tap: .cghidEventTap)
        case .media(let media):
            for down in [true, false] {
                let data = (media.keyCode << 16) | ((down ? 0xA : 0xB) << 8)
                NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                   modifierFlags: .init(rawValue: down ? 0xA00 : 0xB00), timestamp: 0,
                                   windowNumber: 0, context: nil, subtype: 8, data1: data, data2: -1)?
                    .cgEvent?.post(tap: .cghidEventTap)
            }
        case .system(let system):
            switch system {
            case .toggleScrollMode, .activateSiri:
                break
            case .sleepDisplay:
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                task.arguments = ["displaysleepnow"]
                try task.run()
            default:
                guard system.shortcut?.post() == true else { throw OutputError.message("无法发送系统操作。") }
            }
        case .text(let text):
            // Split on Character boundaries so emoji and surrogate pairs stay intact.
            let limit = 4000
            let prefixed = text.value.prefix(limit)
            let truncated = text.value.count > limit
            var chunk = ""
            func send(_ value: String) {
                let units = Array(value.utf16)
                for pressed in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: pressed)
                    units.withUnsafeBufferPointer { buffer in
                        event?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                    }
                    event?.post(tap: .cghidEventTap)
                }
            }
            for character in prefixed {
                chunk.append(character)
                if chunk.utf16.count >= 20 { send(chunk); chunk = "" }
            }
            if !chunk.isEmpty { send(chunk) }
            if text.appendReturn {
                _ = KeyboardShortcut(option: KeyboardShortcut.navigationKeys[0], flags: []).post()
            }
            if truncated {
                throw OutputError.message("预设文本超过 \(limit) 字符，已截断输出。")
            }
        case .shortcut, .openApp: break
        }
    }

    enum OutputError: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case .message(let message): message } }
    }
}
