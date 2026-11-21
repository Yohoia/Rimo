import Foundation
import Security
import Darwin

struct HelperError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// The service runs from the root-owned directory written by deploy-voice.sh.
// It never executes code from the user-writable application bundle; the client
// signing requirement recorded at deployment binds XPC peers to that Rimo build.
final class ServiceInstallation: @unchecked Sendable {
    let directory: URL
    let requirement: String

    init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidpath(getpid(), &path, UInt32(path.count)) > 0 else {
                throw HelperError("无法确定语音服务安装位置。")
            }
            let executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            self.directory = URL(fileURLWithPath: executable).resolvingSymlinksInPath().deletingLastPathComponent()
        }
        let text = (try? String(contentsOf: self.directory.appendingPathComponent("client-requirement"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parsed: SecRequirement?
        guard !text.isEmpty, SecRequirementCreateWithString(text as CFString, [], &parsed) == errSecSuccess else {
            throw HelperError("语音服务缺少有效的客户端签名要求，请在 Rimo 中重新安装语音组件。")
        }
        requirement = text
    }

    func run(_ executable: URL, _ arguments: [String]) throws -> Data {
        let task = Process()
        let output = Pipe()
        let errors = Pipe()
        task.executableURL = executable
        task.arguments = arguments
        task.standardOutput = output
        task.standardError = errors
        try task.run()
        // Fixed-operation tools return small bounded results. Read concurrently
        // so an unexpected error cannot fill a pipe and deadlock waitUntilExit.
        let collected = ToolOutput()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { collected.output = output.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { collected.error = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while task.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if task.isRunning {
            task.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if task.isRunning { kill(task.processIdentifier, SIGKILL) }
        }
        task.waitUntilExit()
        group.wait()
        guard task.terminationStatus == 0 else {
            let message = String(data: collected.error.prefix(2048), encoding: .utf8) ?? "语音服务操作失败。"
            throw HelperError(message.isEmpty ? "语音服务操作超时或执行失败。" : message)
        }
        return collected.output
    }

    func environment(_ operation: String) throws -> Data {
        try run(directory.appendingPathComponent("voice-environment"), [operation])
    }
}

private final class ToolOutput: @unchecked Sendable {
    // Independent fields, each written by one reader and consumed after group.wait.
    var output = Data()
    var error = Data()
}

final class VoiceHelperServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let application: ServiceInstallation
    let queue = DispatchQueue(label: "cn.yohoia.rimo.helper.operations")
    // Confined to queue, permits exactly one capture across all clients.
    var captureOwner: UUID?

    init(application: ServiceInstallation) { self.application = application }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        connection.setCodeSigningRequirement(application.requirement)
        let session = VoiceHelperSession(server: self, connection: connection)
        connection.exportedInterface = NSXPCInterface(with: VoiceHelperProtocol.self)
        connection.exportedObject = session
        connection.remoteObjectInterface = NSXPCInterface(with: VoiceClientProtocol.self)
        connection.invalidationHandler = { session.disconnect() }
        connection.interruptionHandler = { session.disconnect() }
        connection.resume()
        return true
    }
}

final class VoiceHelperSession: NSObject, VoiceHelperProtocol, @unchecked Sendable {
    private let server: VoiceHelperServer
    private weak var connection: NSXPCConnection?
    private let identity = UUID()
    private var disconnected = false
    private var task: Process?
    private var folder: URL?
    private var errors: FileHandle?
    private var stopping = false
    private var captureToken = ""

    init(server: VoiceHelperServer, connection: NSXPCConnection) {
        self.server = server
        self.connection = connection
    }

    func handshake(reply: @escaping (Int) -> Void) { reply(VoiceHelperContract.version) }

    func perform(_ operation: String, reply: @escaping (Data?, String?) -> Void) {
        let response = OperationReply(reply)
        server.queue.async { [self] in
            do {
                guard !disconnected else { throw HelperError("语音助手连接已关闭。") }
                if operation != "status", server.captureOwner != nil { throw HelperError("请先停止语音采集。") }
                guard ["status", "configure"].contains(operation) else { throw HelperError("不支持的语音服务操作。") }
                // Re-applies the capture settings if macOS or another tool reset them.
                let data = try server.application.environment(operation)
                response.reply(data, nil)
            } catch { response.reply(nil, error.localizedDescription) }
        }
    }

    func startCapture(_ token: String, reply: @escaping (FileHandle?, String?) -> Void) {
        let response = CaptureReply(reply)
        server.queue.async { [self] in
            guard UUID(uuidString: token) != nil, !disconnected, server.captureOwner == nil else {
                response.reply(nil, "语音采集已在运行或连接已关闭。")
                return
            }
            do {
                let cli = server.application.directory.appendingPathComponent("PacketLogger.app/Contents/Resources/packetlogger")
                // Validate Apple's binary separately before privileged execution.
                _ = try server.application.run(URL(fileURLWithPath: "/usr/bin/codesign"),
                    ["--verify", "--strict", "-R=anchor apple", cli.path])
                let root = URL(fileURLWithPath: "/private/var/run/Rimo-voice-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700])
                folder = root
                let fifo = root.appendingPathComponent("trace.pipe").path
                guard mkfifo(fifo, 0o600) == 0 else { throw HelperError("无法创建音频管道。") }
                let descriptor = open(fifo, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
                guard descriptor >= 0 else { throw HelperError("无法打开音频管道。") }
                let reader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                let process = Process()
                let errorFile = root.appendingPathComponent("error.txt")
                guard FileManager.default.createFile(atPath: errorFile.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]) else { throw HelperError("无法创建采集诊断文件。") }
                let errors = try FileHandle(forWritingTo: errorFile)
                process.executableURL = cli
                process.arguments = ["convert", "--output", fifo]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = errors
                process.terminationHandler = { [weak self] _ in self?.ended() }
                self.errors = errors
                self.task = process
                stopping = false
                captureToken = token
                server.captureOwner = identity
                try process.run()
                response.reply(reader, nil)
            } catch {
                cleanup()
                response.reply(nil, error.localizedDescription)
            }
        }
    }

    func stopCapture(reply: @escaping () -> Void) {
        let response = StopReply(reply)
        server.queue.async { [self] in
            stop()
            response.reply()
        }
    }

    func disconnect() {
        server.queue.async { [self] in disconnected = true; stop() }
    }

    private func stop() {
        stopping = true
        guard let task, task.isRunning else { cleanup(); return }
        task.terminate()
        let pid = task.processIdentifier
        server.queue.asyncAfter(deadline: .now() + 2) { [weak self, weak task] in
            guard let self, self.task === task, task?.isRunning == true else { return }
            kill(pid, SIGKILL)
        }
    }

    private func ended() {
        server.queue.async { [self] in
            try? errors?.close()
            let data = folder.flatMap { try? Data(contentsOf: $0.appendingPathComponent("error.txt")) } ?? Data()
            let reason = stopping ? "" : String(data: data.prefix(2048), encoding: .utf8) ?? "蓝牙采集已结束。"
            cleanup()
            if !disconnected {
                (connection?.remoteObjectProxy as? VoiceClientProtocol)?.captureEnded(captureToken, message: reason)
            }
        }
    }

    private func cleanup() {
        task = nil
        try? errors?.close()
        errors = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        if server.captureOwner == identity { server.captureOwner = nil }
    }
}

// NSObject XPC callbacks cross queues through immutable closures.
private final class OperationReply: @unchecked Sendable {
    let reply: (Data?, String?) -> Void
    init(_ reply: @escaping (Data?, String?) -> Void) { self.reply = reply }
}
private final class CaptureReply: @unchecked Sendable {
    let reply: (FileHandle?, String?) -> Void
    init(_ reply: @escaping (FileHandle?, String?) -> Void) { self.reply = reply }
}
private final class StopReply: @unchecked Sendable {
    let reply: () -> Void
    init(_ reply: @escaping () -> Void) { self.reply = reply }
}

#if !HELPER_TESTING
@main
struct VoiceHelperMain {
    static func main() {
        do {
            guard geteuid() == 0 else { throw HelperError("语音服务必须由系统启动。") }
            let application = try ServiceInstallation()
            let server = VoiceHelperServer(application: application)
            let listener = NSXPCListener(machServiceName: VoiceHelperContract.label)
            listener.setConnectionCodeSigningRequirement(application.requirement)
            listener.delegate = server
            listener.resume()
            withExtendedLifetime(server) { RunLoop.current.run() }
        } catch {
            NSLog("Rimo voice service startup failed: %@", error.localizedDescription)
            FileHandle.standardError.write(Data(error.localizedDescription.utf8))
            exit(1)
        }
    }
}

#endif
