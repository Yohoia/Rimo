import AppKit
import AVFoundation
import Combine

@MainActor
final class VoiceController: ObservableObject {
    let microphone = MicrophoneBridge()
    enum State: Equatable {
        case off, authorizing, waiting, ready, recording, failed(String)
        var title: String {
            switch self {
            case .off: "遥控器收音未启用"
            case .authorizing: "等待管理员授权…"
            case .waiting: "等待遥控器语音连接…"
            case .ready: "已就绪，按住 Siri 键说话"
            case .recording: "正在收音，松开 Siri 键结束"
            case .failed(let message): message
            }
        }
    }
    @Published private(set) var state: State = .off
    @Published private(set) var level = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var lastRecording: URL?
    @Published private(set) var lastDuration = 0.0
    @Published private(set) var detail: String?
    @Published private(set) var playing = false
    var enabled: Bool { process != nil }

    private var address: String?
    private var process: Process?
    private var session: URL?
    private var handle: FileHandle?
    private var timer: Timer?
    private var parser = PacketStream()
    private var remote: RemoteVoicePackets?
    private var recording: VoiceRecording?
    private var releaseTime: Date?
    private var frameTime: Date?
    private var recordStart: Date?
    private var blockedUntilRelease = false
    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var authorizationError: Pipe?
    private var generation = UUID()
    private var stopping = false
    private var microphoneChanges: AnyCancellable?

    init() {
        microphoneChanges = microphone.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func setAddress(_ value: String?) {
        // Keep the known address through disconnects so HCI reconnection events
        // can identify the same remote without accepting unrelated BLE traffic.
        guard let value, value != address else { return }
        address = value
        if enabled { stop() }
    }

    func start() {
        guard process == nil else { return }
        guard let address else { state = .failed("请先在系统蓝牙设置中连接一只 A2540，再点重新检测。"); return }
        do {
            remote = try RemoteVoicePackets(address: address)
            parser = PacketStream()
            let bundle = Bundle.main
            guard let root = bundle.resourceURL,
                  bundle.url(forResource: "capture-voice", withExtension: "sh") != nil else {
                throw VoiceError.message("缺少收音组件，请重新构建 sofo。")
            }
            let cli = root.appendingPathComponent("PacketLogger.app/Contents/Resources/packetlogger")
            guard FileManager.default.isExecutableFile(atPath: cli.path) else {
                throw VoiceError.message("此构建未包含 Apple PacketLogger。请按项目 README 配置收音工具后重新构建。")
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sofo-voice-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            for name in ["trace.pklg", "error.txt"] {
                guard FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw VoiceError.message("无法创建临时收音文件。")
                }
            }
            session = folder
            handle = try FileHandle(forReadingFrom: folder.appendingPathComponent("trace.pklg"))
            let shell = ["/bin/bash", root.appendingPathComponent("capture-voice.sh").path, cli.path, folder.path,
                         String(ProcessInfo.processInfo.processIdentifier)].map(shellQuote).joined(separator: " ")
            let script = "with timeout of 28830 seconds\n do shell script \(appleQuote(shell)) with administrator privileges with prompt \"sofo 需要采集遥控器的蓝牙音频。停止收音或退出 sofo 后采集会结束。\"\nend timeout"
            let task = Process()
            let errors = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            task.standardError = errors
            task.standardOutput = FileHandle.nullDevice
            let token = UUID()
            generation = token
            stopping = false
            task.terminationHandler = { [weak self] _ in
                Task { @MainActor in self?.processEnded(token: token) }
            }
            authorizationError = errors
            process = task
            state = .authorizing
            detail = nil
            try task.run()
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        } catch {
            finishProcess()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        guard process != nil else { return }
        stopping = true
        finishRecording()
        signalStop()
        microphone.reset()
        state = .off
        level = 0
        // Keep polling until the privileged foreground process has actually exited.
        // Its parent watchdog also ends capture when sofo exits unexpectedly.
    }

    func shutdown() {
        stopping = true
        finishRecording()
        signalStop()
        timer?.invalidate()
        timer = nil
        playbackTimer?.invalidate()
        player?.stop()
        microphone.shutdown()
    }

    func playLastRecording() {
        if playing {
            playbackTimer?.invalidate()
            player?.stop(); playing = false
            return
        }
        guard let lastRecording else { return }
        do {
            player = try AVAudioPlayer(contentsOf: lastRecording)
            guard player?.play() == true else { throw VoiceError.message("无法播放录音，请在访达中打开。") }
            playing = true
            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: player?.duration ?? 0.1, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.playing = false }
            }
        } catch { detail = error.localizedDescription }
    }

    func revealRecordings() {
        guard let lastRecording else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecording])
    }

    private func poll() {
        do {
            if let data = try handle?.read(upToCount: 262_144), !data.isEmpty {
                for record in try parser.append(data) {
                    let events = remote?.consume(record) ?? []
                    guard !stopping else { continue }
                    if state == .authorizing { state = .waiting }
                    for event in events { try consume(event) }
                }
            }
            let now = Date()
            if let releaseTime, now.timeIntervalSince(releaseTime) > 0.25 { finishRecording() }
            if let recordStart, now.timeIntervalSince(recordStart) > 60 {
                finishRecording()
                blockedUntilRelease = true
                detail = "已达到单次 60 秒上限。松开 Siri 键后可以再次录音。"
            } else if recording != nil, let frameTime, now.timeIntervalSince(frameTime) > 2 {
                finishRecording()
                blockedUntilRelease = true
                detail = "音频传输中断，本段录音已结束。松开 Siri 键后重试。"
            }
            if playing, player?.isPlaying != true { playing = false }
        } catch {
            detail = error.localizedDescription
            stop()
            state = .failed(error.localizedDescription)
        }
    }

    private func consume(_ event: RemoteVoicePackets.Event) throws {
        switch event {
        case .connected:
            blockedUntilRelease = false
            state = .ready
        case .disconnected:
            finishRecording()
            microphone.reset()
            state = .waiting
            detail = "遥控器连接已断开，重新连接后可继续收音。"
        case .button(true):
            guard !blockedUntilRelease else { return }
            finishRecording()
            recording = try VoiceRecording()
            microphone.reset()
            recording?.onPCM = { [weak self] pcm in self?.microphone.push(pcm) }
            recordStart = Date()
            frameTime = Date()
            releaseTime = nil
            duration = 0
            level = 0
            detail = nil
            state = .recording
        case .button(false):
            blockedUntilRelease = false
            releaseTime = Date() // Drain the final audio packets, which follow key-up.
        case .audio(let payload):
            guard !blockedUntilRelease, let recording else { return }
            level = try recording.append(payload)
            duration = recording.duration
            frameTime = Date()
        case .end:
            finishRecording()
        }
    }

    private func finishRecording() {
        guard let recording else { return }
        self.recording = nil
        recordStart = nil; frameTime = nil; releaseTime = nil; level = 0
        if state == .recording { state = .ready }
        guard recording.frames > 0 else {
            detail = "已收到 Siri 按键，但没有音频。请重新按住说话。"
            return
        }
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("sofo/Recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let name = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = folder.appendingPathComponent("A2540-\(name)-\(UUID().uuidString.prefix(6)).wav")
            try recording.save(to: url)
            lastRecording = url
            lastDuration = recording.duration
            let issues = recording.missingFrames + recording.rejectedFrames
            detail = issues > 0 ? "录音已保存，检测到 \(issues) 个丢失或无效音频帧。" : "录音已保存到本机。"
        } catch { detail = "保存录音失败：\(error.localizedDescription)" }
    }

    private func signalStop() {
        if let session { FileManager.default.createFile(atPath: session.appendingPathComponent("stop").path, contents: nil) }
        // An authorization dialog has not launched the shell yet. Terminate the
        // dialog process; a late shell launch still sees the stop marker.
        if state == .authorizing { process?.terminate() }
    }

    private func processEnded(token: UUID) {
        guard generation == token else { return }
        poll() // Drain packets written just before termination.
        let wasStopping = stopping
        finishRecording()
        let localError = session.flatMap { try? String(contentsOf: $0.appendingPathComponent("error.txt"), encoding: .utf8) } ?? ""
        let authError = authorizationError.flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) } ?? ""
        finishProcess()
        if wasStopping { state = .off }
        else if authError.contains("-128") { state = .off; detail = "已取消管理员授权，未启用收音。" }
        else {
            let reason = localError.trimmingCharacters(in: .whitespacesAndNewlines)
            state = .failed(reason.isEmpty ? "蓝牙采集已结束。请重新启用收音。" : String(reason.prefix(500)))
        }
    }

    private func finishProcess() {
        timer?.invalidate(); timer = nil
        try? handle?.close(); handle = nil
        if let session { try? FileManager.default.removeItem(at: session) }
        session = nil; process = nil; authorizationError = nil
        remote = nil
    }

    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func appleQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
