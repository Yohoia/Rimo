import Foundation

struct SystemShortcut: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
}

enum RemoteAction: Codable, Equatable {
    case keyboard(KeyboardShortcut)
    case shortcut(SystemShortcut)

    var title: String {
        switch self {
        case .keyboard(let key): key.title
        case .shortcut(let shortcut): shortcut.name
        }
    }
}

struct ButtonMappings: Codable, Equatable {
    var actions: [String: RemoteAction] = [:]
    private var disabled: Set<String> = []

    subscript(_ button: RemoteButton) -> RemoteAction? {
        get { actions[button.rawValue] }
        set { actions[button.rawValue] = newValue }
    }

    func isEnabled(_ button: RemoteButton) -> Bool { !disabled.contains(button.rawValue) }

    mutating func setEnabled(_ enabled: Bool, for button: RemoteButton) {
        if enabled { disabled.remove(button.rawValue) } else { disabled.insert(button.rawValue) }
    }
}

struct AppSceneMapping: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    var enabled = true
    var buttons: ButtonMappings
}

struct RemoteConfiguration: Codable, Equatable {
    var global = ButtonMappings()
    var scenes: [AppSceneMapping] = []
    var automatic = false

    func scene(for id: String?) -> AppSceneMapping? {
        guard automatic, let id else { return nil }
        return scenes.first { $0.id == id && $0.enabled }
    }

    func action(for button: RemoteButton, in appID: String?) -> RemoteAction? {
        let buttons = scene(for: appID)?.buttons ?? global
        return buttons.isEnabled(button) ? buttons[button] : nil
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
