import AppKit
import Combine
import Foundation
import Security

/// Connects to Rimo's root voice service. The service is deployed once with a
/// single administrator prompt (no Login Items approval, no restart) and then
/// reused for every capture until Rimo ships different voice components.
@MainActor
final class VoiceHelperClient: ObservableObject {
    static let shared = VoiceHelperClient()

    enum Installation: Equatable {
        case missing, outdated, installed, unavailable(String)
    }

    @Published private(set) var installation: Installation = .missing
    @Published private(set) var deploying = false
    @Published private(set) var connected = false
    private var connection: NSXPCConnection?
    private var connectionID = UUID()
    private var captureToken: String?
    private var readiness: Task<Void, Error>?
    private var pending: [UUID: CheckedContinuation<HelperResponse, Error>] = [:]
    var onCaptureEnded: ((String) -> Void)?

    static let serviceDirectory = URL(fileURLWithPath: "/Library/Application Support/Rimo/VoiceService")
    private static let daemon = "/Library/LaunchDaemons/\(VoiceHelperContract.label).plist"

    private enum HelperResponse {
        case version(Int), data(Data), capture(FileHandle), stopped
    }

    init() { refreshStatus() }

    var status: String {
        switch installation {
        case .installed: connected ? "语音组件已就绪" : "语音组件已安装"
        case .outdated: "Rimo 已更新，需要输入一次密码更新语音组件"
        case .missing: "首次启用时安装，只需输入一次密码"
        case .unavailable(let reason): reason
        }
    }

    func refreshStatus() {
        guard let bundled = Self.bundledDeploymentID else {
            installation = .unavailable("此构建未包含语音组件（缺少 PacketLogger）。")
            return
        }
        let read = { (name: String) in
            (try? String(contentsOf: Self.serviceDirectory.appendingPathComponent(name), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let installed = read("deployment-id")
        if installed == nil || !FileManager.default.fileExists(atPath: Self.daemon) { installation = .missing }
        else if installed != bundled || read("client-requirement") != Self.clientRequirement { installation = .outdated }
        else { installation = .installed }
    }

    /// Mirrors deploy-voice.sh: team-signed builds match by team, ad-hoc builds
    /// by exact hash, so every local rebuild needs one new authorization.
    private static let clientRequirement: String? = {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String {
            return "identifier \"cn.yohoia.rimo\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        }
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return text as String
    }()

    /// Deploys components when needed, then connects. The only user interaction
    /// is the system administrator prompt on first use or after an update.
    /// Automatic starts pass `allowDeploy: false` so only a user action can
    /// show the administrator prompt.
    func ensureReady(allowDeploy: Bool = true) async throws {
        if let readiness { return try await readiness.value }
        let attempt = Task { try await connect(allowDeploy: allowDeploy) }
        readiness = attempt
        defer { readiness = nil }
        try await attempt.value
    }

    /// Reinstalls every voice component with one administrator prompt.
    func redeploy() async throws {
        invalidate()
        try await deploy()
        try await ensureReady()
    }

    func uninstall() async throws {
        await stopCapture()
        invalidate()
        guard let script = Bundle.main.url(forResource: "deploy-voice", withExtension: "sh") else {
            throw VoiceError.message("缺少语音组件卸载脚本，请重新安装 Rimo。")
        }
        try await Self.runAsAdministrator(["/bin/bash", script.path, "--uninstall"],
            prompt: "Rimo 将移除遥控器语音组件，并还原蓝牙诊断设置。")
        refreshStatus()
    }

    private func connect(allowDeploy: Bool) async throws {
        refreshStatus()
        if case .unavailable(let reason) = installation { throw VoiceError.message(reason) }
        if connected, installation == .installed { return }
        if installation != .installed {
            guard allowDeploy else { throw VoiceError.message(status) }
            invalidate()
            try await deploy()
        }
        do { try await handshake() }
        catch {
            guard allowDeploy else { throw error }
            // A stale or crashed service is repaired with the same single prompt.
            invalidate()
            try await deploy()
            try await handshake()
        }
    }

    private func deploy() async throws {
        guard let script = Bundle.main.url(forResource: "deploy-voice", withExtension: "sh") else {
            throw VoiceError.message("缺少语音组件安装脚本，请重新安装 Rimo。")
        }
        deploying = true
        defer { deploying = false; refreshStatus() }
        try await Self.runAsAdministrator(["/bin/bash", script.path, Bundle.main.bundlePath],
            prompt: "Rimo 将安装遥控器语音组件：后台采集服务、蓝牙语音配置和 Rimo Remote Microphone。")
        refreshStatus()
        guard installation == .installed else { throw VoiceError.message("语音组件安装未完成，请重试。") }
    }

    private func handshake() async throws {
        let channel = NSXPCConnection(machServiceName: VoiceHelperContract.label, options: .privileged)
        channel.setCodeSigningRequirement(#"identifier "cn.yohoia.rimo.voice-helper""#)
        channel.remoteObjectInterface = NSXPCInterface(with: VoiceHelperProtocol.self)
        channel.exportedInterface = NSXPCInterface(with: VoiceClientProtocol.self)
        channel.exportedObject = HelperEvents(client: self)
        let token = UUID()
        connectionID = token
        channel.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connectionLost(token: token) }
        }
        channel.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.connectionLost(token: token) }
        }
        connection = channel
        channel.resume()
        guard case .version(let version) = try await request(timeout: 5, { proxy, id in
            proxy.handshake { [weak self] version in
                Task { @MainActor in self?.finish(id, .success(.version(version))) }
            }
        }), version == VoiceHelperContract.version else {
            invalidate()
            throw VoiceError.message("语音服务版本不匹配。")
        }
        connected = true
    }

    func perform(_ operation: String) async throws -> [String: Bool] {
        try await ensureReady(allowDeploy: false)
        let response = try await request { proxy, id in
            proxy.perform(operation) { [weak self] data, message in
                Task { @MainActor in
                    if let message { self?.finish(id, .failure(VoiceError.message(message))) }
                    else { self?.finish(id, .success(.data(data ?? Data()))) }
                }
            }
        }
        guard case .data(let data) = response,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
            throw VoiceError.message("语音服务返回了无效结果。")
        }
        return result
    }

    func startCapture() async throws -> Int32 {
        try await ensureReady(allowDeploy: false)
        let token = UUID().uuidString
        captureToken = token
        let response = try await request { proxy, id in
            proxy.startCapture(token) { [weak self] handle, message in
                Task { @MainActor in
                    if let message { self?.finish(id, .failure(VoiceError.message(message))) }
                    else if let handle { self?.finish(id, .success(.capture(handle))) }
                    else { self?.finish(id, .failure(VoiceError.message("语音服务没有返回音频管道。"))) }
                }
            }
        }
        guard case .capture(let handle) = response else { throw VoiceError.message("音频管道无效。") }
        let descriptor = dup(handle.fileDescriptor)
        guard descriptor >= 0 else { throw VoiceError.message("无法打开音频管道。") }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        return descriptor
    }

    func stopCapture() async {
        captureToken = nil
        guard connected else { return }
        _ = try? await request { proxy, id in
            proxy.stopCapture { [weak self] in
                Task { @MainActor in self?.finish(id, .success(.stopped)) }
            }
        }
    }

    func captureEnded(token: String, message: String) {
        guard captureToken == token else { return }
        captureToken = nil
        onCaptureEnded?(message)
    }

    func shutdown() { invalidate() }

    private func request(timeout: Double = 30, _ send: (VoiceHelperProtocol, UUID) -> Void) async throws -> HelperResponse {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            guard let connection else {
                continuation.resume(throwing: VoiceError.message("语音服务未连接。"))
                return
            }
            pending[id] = continuation
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                let message = error.localizedDescription
                Task { @MainActor in self?.finish(id, .failure(VoiceError.message(message))) }
            } as? VoiceHelperProtocol
            guard let proxy else {
                finish(id, .failure(VoiceError.message("无法连接语音服务。")))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, self.pending[id] != nil else { return }
                self.finish(id, .failure(VoiceError.message("语音服务响应超时，请重试。")))
                self.invalidate()
            }
            send(proxy, id)
        }
    }

    private func finish(_ id: UUID, _ result: Result<HelperResponse, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func connectionLost(token: UUID) {
        guard connectionID == token else { return }
        let wasConnected = connected
        invalidate()
        if wasConnected { onCaptureEnded?("语音服务连接中断，请重新启用语音。") }
    }

    private func invalidate() {
        connectionID = UUID()
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        connected = false
        captureToken = nil
        let requests = Array(pending.values)
        pending.removeAll()
        for request in requests { request.resume(throwing: VoiceError.message("语音服务连接已关闭。")) }
    }

    /// The deployment ID changes whenever any bundled voice component changes.
    private static var bundledDeploymentID: String? {
        guard Bundle.main.url(forResource: "PacketLogger", withExtension: "app") != nil,
              let url = Bundle.main.url(forResource: "voice-deployment-id", withExtension: nil),
              let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shows the standard macOS administrator prompt once and runs a fixed script.
    private static func runAsAdministrator(_ arguments: [String], prompt: String) async throws {
        let command = arguments.map { "'" + $0.replacingOccurrences(of: "'", with: #"'\''"#) + "'" }.joined(separator: " ")
        func literal(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = "do shell script \(literal(command + " 2>&1")) with prompt \(literal(prompt)) with administrator privileges"
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let text = String(decoding: data, as: UTF8.self)
                if text.contains("-128") { throw VoiceError.message("已取消安装语音组件。") }
                // osascript prefixes "execution error:"; keep the script's own message.
                let message = text.components(separatedBy: "execution error: ").last?
                    .replacingOccurrences(of: #"\s*\(-?\d+\)\s*$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw VoiceError.message(message?.isEmpty == false ? message! : "语音组件安装失败。")
            }
        }.value
    }
}

private final class HelperEvents: NSObject, VoiceClientProtocol, @unchecked Sendable {
    weak var client: VoiceHelperClient?
    init(client: VoiceHelperClient) { self.client = client }
    func captureEnded(_ token: String, message: String) {
        Task { @MainActor [weak self] in self?.client?.captureEnded(token: token, message: message) }
    }
}
