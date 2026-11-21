import AppKit
import Carbon.HIToolbox
import Foundation

struct SystemShortcut: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
}

enum RemoteAction: Codable, Equatable {
    case keyboard(KeyboardShortcut)
    case shortcut(SystemShortcut)
    case mouse(MouseAction)
    case scroll(ScrollAction)
    case media(MediaAction)
    case system(SystemAction)
    case openApp(AppTarget)
    case text(TextAction)

    func isAssignable(to button: RemoteButton) -> Bool {
        self != .system(.toggleScrollMode) || ScrollAction.Direction(button: button) == nil
    }

    var title: String {
        switch self {
        case .keyboard(let key): key.title
        case .shortcut(let shortcut): shortcut.name
        case .mouse(let action): action.title
        case .scroll(let action): "\(action.direction.title) · \(action.amount)"
        case .media(let action): action.title
        case .system(let action): action.title
        case .openApp(let app): "打开 \(app.name)"
        case .text: "输入预设文本"
        }
    }

    var holdsUntilRelease: Bool {
        if case .keyboard(let key) = self { return key.holdsUntilRelease == true }
        return false
    }

    /// Voxa's model: the remote "presses the input method's voice key and
    /// supplies the audio". A lone modifier (Fn, Option, Command, Control,
    /// Shift) is how Typeless, Doubao, WeChat and similar apps start listening,
    /// so only these mappings route the remote microphone.
    var startsVoiceInput: Bool {
        guard case .keyboard(let key) = self else { return false }
        return key.modifiers & ~UInt64(NSEvent.ModifierFlags.function.rawValue) == 0
            && KeyboardShortcut.modifierFlag(for: key.keyCode) != nil
    }
}

enum MouseAction: String, Codable, CaseIterable, Identifiable {
    case left, right, doubleClick, middle
    var id: Self { self }
    var title: String {
        switch self {
        case .left: "左键单击"
        case .right: "右键点击"
        case .doubleClick: "左键双击"
        case .middle: "中键"
        }
    }
}

struct ScrollAction: Codable, Equatable {
    enum Direction: String, Codable, CaseIterable, Identifiable {
        case up, down, left, right

        init?(button: RemoteButton) {
            switch button {
            case .up: self = .up
            case .down: self = .down
            case .left: self = .left
            case .right: self = .right
            default: return nil
            }
        }

        var id: Self { self }
        var title: String {
            switch self {
            case .up: "向上滚动"
            case .down: "向下滚动"
            case .left: "向左滚动"
            case .right: "向右滚动"
            }
        }
    }
    var direction: Direction = .down
    var amount = 80
    var boundedAmount: Int { min(600, max(10, amount)) }
    var deltas: (vertical: Int32, horizontal: Int32) {
        let value = Int32(boundedAmount)
        switch direction {
        case .up: return (value, 0)
        case .down: return (-value, 0)
        case .left: return (0, value)
        case .right: return (0, -value)
        }
    }
}

enum MediaAction: String, Codable, CaseIterable, Identifiable {
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    var id: Self { self }
    var title: String {
        switch self {
        case .playPause: "播放/暂停"
        case .nextTrack: "下一个"
        case .previousTrack: "上一个"
        case .volumeUp: "音量升高"
        case .volumeDown: "音量降低"
        case .mute: "扬声器静音/取消静音"
        }
    }
    var keyCode: Int {
        switch self {
        case .playPause: 16
        case .nextTrack: 17
        case .previousTrack: 18
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        }
    }
}

enum SystemAction: String, Codable, CaseIterable, Identifiable {
    case toggleScrollMode
    case missionControl, appWindows, previousDesktop, nextDesktop, showDesktop, lockScreen, sleepDisplay
    case activateSiri
    case copy, cut, paste, undo, redo, selectAll, find, back, forward
    case newTab, previousTab, nextTab, zoomIn, zoomOut, resetZoom, captureScreen, screenshotTools, emoji

    // Each action belongs to one browse category; recommendations may surface it again.
    static let windowActions: [Self] = [.missionControl, .appWindows, .showDesktop, .previousDesktop, .nextDesktop]
    static let systemActions: [Self] = [.activateSiri, .lockScreen, .sleepDisplay, .captureScreen, .screenshotTools, .emoji]
    static let editingActions: [Self] = [.copy, .cut, .paste, .undo, .redo, .selectAll, .find]
    static let otherActions: [Self] = [.toggleScrollMode, .back, .forward, .newTab, .previousTab,
        .nextTab, .zoomIn, .zoomOut, .resetZoom]
    var id: Self { self }
    var title: String {
        switch self {
        case .toggleScrollMode: "滚动模式"
        case .missionControl: "调度中心"
        case .appWindows: "App Exposé"
        case .previousDesktop: "桌面向左"
        case .nextDesktop: "桌面向右"
        case .showDesktop: "显示/隐藏桌面"
        case .lockScreen: "锁定"
        case .sleepDisplay: "关闭显示器"
        case .activateSiri: "启动 Siri"
        case .copy: "复制"
        case .cut: "剪切"
        case .paste: "粘贴"
        case .undo: "撤销"
        case .redo: "重做"
        case .selectAll: "全选"
        case .find: "查找"
        case .back: "后退"
        case .forward: "前进"
        case .newTab: "新建浏览器标签页"
        case .previousTab: "上一个标签页（左）"
        case .nextTab: "下一个标签页（右）"
        case .zoomIn: "放大"
        case .zoomOut: "缩小"
        case .resetZoom: "缩放重置"
        case .captureScreen: "全屏截图"
        case .screenshotTools: "打开截屏工具栏"
        case .emoji: "表情符号"
        }
    }
    var shortcut: KeyboardShortcut? {
        let key: Int
        let flags: NSEvent.ModifierFlags
        switch self {
        case .missionControl: (key, flags) = (kVK_UpArrow, .control)
        case .appWindows: (key, flags) = (kVK_DownArrow, .control)
        case .previousDesktop: (key, flags) = (kVK_LeftArrow, .control)
        case .nextDesktop: (key, flags) = (kVK_RightArrow, .control)
        case .showDesktop: (key, flags) = (kVK_F11, [])
        case .lockScreen: (key, flags) = (kVK_ANSI_Q, [.control, .command])
        case .sleepDisplay, .toggleScrollMode, .activateSiri: return nil
        case .copy: (key, flags) = (kVK_ANSI_C, .command)
        case .cut: (key, flags) = (kVK_ANSI_X, .command)
        case .paste: (key, flags) = (kVK_ANSI_V, .command)
        case .undo: (key, flags) = (kVK_ANSI_Z, .command)
        case .redo: (key, flags) = (kVK_ANSI_Z, [.command, .shift])
        case .selectAll: (key, flags) = (kVK_ANSI_A, .command)
        case .find: (key, flags) = (kVK_ANSI_F, .command)
        case .back: (key, flags) = (kVK_ANSI_LeftBracket, .command)
        case .forward: (key, flags) = (kVK_ANSI_RightBracket, .command)
        case .newTab: (key, flags) = (kVK_ANSI_T, .command)
        case .previousTab: (key, flags) = (kVK_Tab, [.control, .shift])
        case .nextTab: (key, flags) = (kVK_Tab, .control)
        case .zoomIn: (key, flags) = (kVK_ANSI_Equal, [.command, .shift])
        case .zoomOut: (key, flags) = (kVK_ANSI_Minus, .command)
        case .resetZoom: (key, flags) = (kVK_ANSI_0, .command)
        case .captureScreen: (key, flags) = (kVK_ANSI_3, [.command, .shift])
        case .screenshotTools: (key, flags) = (kVK_ANSI_5, [.command, .shift])
        case .emoji: (key, flags) = (kVK_Space, [.control, .command])
        }
        return KeyboardShortcut(option: .init(id: UInt16(key), title: title), flags: flags)
    }
}

struct RemoteScrollMode {
    private(set) var enabled = false

    mutating func toggle() { enabled.toggle() }
    mutating func reset() { enabled = false }

    func scroll(for button: RemoteButton) -> ScrollAction? {
        guard enabled, let direction = ScrollAction.Direction(button: button) else { return nil }
        return .init(direction: direction)
    }
}

struct AppTarget: Codable, Equatable {
    let bundleIdentifier: String
    let name: String
    var path: String? = nil

    static func at(_ url: URL) -> Self? {
        guard url.isFileURL else { return nil }
        let url = url.standardizedFileURL
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return Self(bundleIdentifier: identifier, name: name, path: url.path)
    }

    var installedURL: URL? {
        if let path, FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if Self.at(url)?.bundleIdentifier == bundleIdentifier { return url }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

struct TextAction: Codable, Equatable {
    var value = ""
    var appendReturn = false
}

struct ButtonMappings: Codable, Equatable {
    var actions: [String: RemoteAction] = [:]
    private var disabled: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey { case actions, disabled }

    /// Skips actions this build cannot decode (from short-lived development
    /// builds) instead of failing to load every mapping.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        disabled = try container.decodeIfPresent(Set<String>.self, forKey: .disabled) ?? []
        let raw = try container.decodeIfPresent([String: OptionalAction].self, forKey: .actions) ?? [:]
        actions = raw.compactMapValues(\.action)
    }

    private struct OptionalAction: Decodable {
        let action: RemoteAction?
        init(from decoder: Decoder) throws { action = try? RemoteAction(from: decoder) }
    }

    subscript(_ button: RemoteButton, _ trigger: RemoteTrigger = .single) -> RemoteAction? {
        get { actions[trigger.mappingKey(for: button)] }
        set { actions[trigger.mappingKey(for: button)] = newValue }
    }

    func isEnabled(_ button: RemoteButton, trigger: RemoteTrigger = .single) -> Bool {
        !disabled.contains(trigger.mappingKey(for: button))
    }

    mutating func setEnabled(_ enabled: Bool, for button: RemoteButton, trigger: RemoteTrigger = .single) {
        let key = trigger.mappingKey(for: button)
        if enabled { disabled.remove(key) } else { disabled.insert(key) }
    }
}

struct AppSceneMapping: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var enabled = true
    var buttons: ButtonMappings
    // Older and manually created scenes keep their full copy of the mapping.
    private(set) var overrides: Set<String>? = nil

    var canFollowGlobal: Bool { overrides != nil }

    func inherits(_ button: RemoteButton, trigger: RemoteTrigger = .single) -> Bool {
        overrides?.contains(trigger.mappingKey(for: button)) == false
    }

    func source(for button: RemoteButton, trigger: RemoteTrigger = .single, global: ButtonMappings) -> ButtonMappings {
        inherits(button, trigger: trigger) ? global : buttons
    }

    func resolved(global: ButtonMappings) -> ButtonMappings {
        guard let overrides else { return buttons }
        var result = global
        for trigger in RemoteTrigger.allCases {
            for button in RemoteButton.allCases where overrides.contains(trigger.mappingKey(for: button)) {
                result[button, trigger] = buttons[button, trigger]
                result.setEnabled(buttons.isEnabled(button, trigger: trigger), for: button, trigger: trigger)
            }
        }
        return result
    }

    mutating func edit(_ button: RemoteButton, trigger: RemoteTrigger = .single,
                       global: ButtonMappings, _ change: (inout ButtonMappings) -> Void) {
        if inherits(button, trigger: trigger) {
            buttons[button, trigger] = global[button, trigger]
            buttons.setEnabled(global.isEnabled(button, trigger: trigger), for: button, trigger: trigger)
            overrides?.insert(trigger.mappingKey(for: button))
        }
        change(&buttons)
    }

    mutating func followGlobal(_ button: RemoteButton, trigger: RemoteTrigger = .single) {
        guard overrides != nil else { return }
        overrides?.remove(trigger.mappingKey(for: button))
        buttons[button, trigger] = nil
        buttons.setEnabled(true, for: button, trigger: trigger)
    }
}

enum ScenePreset: String, CaseIterable, Identifiable {
    case presentation, reading, webVideo

    var id: Self { self }

    var title: String {
        switch self {
        case .presentation: "演示翻页"
        case .reading: "长文阅读"
        case .webVideo: "网页视频"
        }
    }

    var detail: String {
        switch self {
        case .presentation: "用于 Keynote 和 PowerPoint 的放映模式。"
        case .reading: "在 Safari 阅读网页，或在「预览」阅读 PDF。"
        case .webVideo: "用于 YouTube。使用前先点一下视频播放器。"
        }
    }

    var symbol: String {
        switch self {
        case .presentation: "rectangle.on.rectangle"
        case .reading: "book"
        case .webVideo: "play.rectangle"
        }
    }

    struct Binding: Identifiable {
        let button: RemoteButton
        let purpose: String
        let action: RemoteAction

        var id: RemoteButton { button }
        init(_ button: RemoteButton, _ purpose: String, _ key: Int, _ label: String) {
            self.button = button
            self.purpose = purpose
            self.action = .keyboard(KeyboardShortcut(option: .init(id: UInt16(key), title: label), flags: []))
        }

        init(_ button: RemoteButton, _ action: RemoteAction) {
            self.button = button
            self.purpose = action.title
            self.action = action
        }
    }

    var bindings: [Binding] {
        let specialized: [Binding] = switch self {
        case .presentation: [
            .init(.left, "上一张", kVK_LeftArrow, "←"),
            .init(.right, "下一张或播放下一段动画", kVK_RightArrow, "→"),
            .init(.back, "退出放映", kVK_Escape, "Esc")
        ]
        case .reading: [
            .init(.up, "向上滚动一屏", kVK_PageUp, "⇞"),
            .init(.down, "向下滚动一屏", kVK_PageDown, "⇟")
        ]
        case .webVideo: [
            .init(.select, "播放 / 暂停", kVK_ANSI_K, "K"),
            .init(.left, "后退 10 秒", kVK_ANSI_J, "J"),
            .init(.right, "前进 10 秒", kVK_ANSI_L, "L"),
            .init(.down, "切换全屏", kVK_ANSI_F, "F")
        ]
        }
        return RemoteButton.a2540Buttons.compactMap { button in
            specialized.first { $0.button == button } ?? Self.defaultBindings.first { $0.button == button }
        }
    }

    static var defaultBindings: [Binding] { [
        .init(.up, "向上", kVK_UpArrow, "↑"),
        .init(.down, "向下", kVK_DownArrow, "↓"),
        .init(.left, "向左", kVK_LeftArrow, "←"),
        .init(.right, "向右", kVK_RightArrow, "→"),
        .init(.select, "确认", kVK_Return, "↩"),
        .init(.back, "返回 / 退出", kVK_Escape, "Esc"),
        .init(.home, .system(.missionControl)),
        .init(.playPause, .media(.playPause)),
        .init(.mute, .media(.mute)),
        .init(.volumeUp, .media(.volumeUp)),
        .init(.volumeDown, .media(.volumeDown)),
        .init(.power, .system(.sleepDisplay)),
        .init(.siri, .system(.activateSiri))
    ] }
}

struct RemoteConfiguration: Codable, Equatable {
    var global = ButtonMappings()
    var scenes: [AppSceneMapping] = []
    var automatic = false

    mutating func completeSceneMappings() {
        for index in scenes.indices {
            for binding in ScenePreset.defaultBindings {
                let scene = scenes[index]
                let source = scene.source(for: binding.button, global: global)
                guard source[binding.button] == nil,
                      source.isEnabled(binding.button),
                      scene.inherits(binding.button) || scene.overrides == nil else { continue }
                scenes[index].edit(binding.button, global: global) { $0[binding.button] = binding.action }
            }
        }
    }

    func scene(for id: String?) -> AppSceneMapping? {
        guard automatic, let id else { return nil }
        return scenes.first { $0.id == id && $0.enabled }
    }

    func action(for button: RemoteButton, trigger: RemoteTrigger = .single, in appID: String?) -> RemoteAction? {
        let buttons = scene(for: appID)?.source(for: button, trigger: trigger, global: global) ?? global
        guard buttons.isEnabled(button, trigger: trigger),
              let action = buttons[button, trigger], action.isAssignable(to: button) else { return nil }
        return action
    }

    mutating func apply(_ preset: ScenePreset, to id: String, name: String) {
        let index: Int
        if let existing = scenes.firstIndex(where: { $0.id == id }) {
            index = existing
        } else {
            index = scenes.count
            scenes.append(AppSceneMapping(id: id, name: name, buttons: ButtonMappings(), overrides: []))
        }
        for binding in preset.bindings {
            scenes[index].edit(binding.button, global: global) {
                $0[binding.button] = binding.action
                $0.setEnabled(true, for: binding.button)
            }
        }
    }
}

enum ShortcutsCLI {
    static func list() async throws -> [SystemShortcut] {
        try await Task.detached(priority: .utility) {
            let output = try execute(["list", "--show-identifiers"])
            return output.split(whereSeparator: \.isNewline).compactMap { line in
                guard line.hasSuffix(")"), let boundary = line.range(of: " (", options: .backwards),
                      let id = UUID(uuidString: String(line[boundary.upperBound..<line.index(before: line.endIndex)]))
                else { return nil }
                return SystemShortcut(id: id, name: String(line[..<boundary.lowerBound]))
            }
        }.value
    }

    static func run(_ shortcut: SystemShortcut) async throws {
        try await Task.detached(priority: .userInitiated) {
            _ = try execute(["run", shortcut.id.uuidString], discardOutput: true)
        }.value
    }

    private static func execute(_ arguments: [String], discardOutput: Bool = false) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        process.standardOutput = discardOutput ? FileHandle.nullDevice : pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + (discardOutput ? 60 : 15), execute: timeout)
        defer { timeout.cancel() }
        // Drain before waiting so a large shortcut library cannot fill the pipe.
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let detail = process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGTERM
                ? "等待快捷指令响应超时。" : output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CommandFailure(detail: detail)
        }
        return output
    }

    private struct CommandFailure: LocalizedError {
        let detail: String
        var errorDescription: String? { detail.isEmpty ? "快捷指令未能完成。" : detail }
    }
}
