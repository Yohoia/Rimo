import Foundation
import CoreAudio
import Darwin

// Apple protocol events drive a segment. Decoded PCM leaves through onPCM;
// microphone output is independent of packet framing.
final class VoiceSession {
    enum Phase: Sendable { case waiting, ready, recording, draining }
    private(set) var phase: Phase = .waiting
    private(set) var level = 0.0
    private(set) var duration = 0.0
    private(set) var detail: String?
    private(set) var recording: VoiceRecording?
    private var started: Double?
    private var lastFrame: Double?
    private var released: Double?
    private var blocked = false
    private var connected = false
    var onPCM: (([Int16]) -> Void)?
    var onFinished: ((VoiceRecording) -> Void)?

    func consume(_ event: RemoteVoicePackets.Event, at now: Double) throws {
        switch event {
        case .connected:
            finish()
            connected = true
            blocked = false
            phase = .ready
        case .disconnected:
            finish()
            connected = false
            blocked = false
            phase = .waiting
            detail = "遥控器已断开，连接恢复后可继续收音。"
        case .button(true):
            guard !blocked else { return }
            finish()
            let next = try VoiceRecording()
            next.onPCM = { [weak self] in self?.onPCM?($0) }
            recording = next
            started = now
            lastFrame = now
            released = nil
            duration = 0
            level = 0
            detail = nil
            phase = .recording
        case .button(false):
            blocked = false
            if recording != nil { released = now; phase = .draining }
        case .audio(let payload):
            guard !blocked, let recording else { return }
            let frames = recording.frames
            level = try recording.append(payload)
            duration = recording.duration
            if recording.frames > frames { lastFrame = now }
        case .end:
            if recording != nil {
                blocked = released == nil
                finish()
            }
        }
    }

    func tick(at now: Double, pendingAudio: Bool) {
        if let released, now - released >= 0.25 { finish() }
        if let started, now - started >= 60 {
            finish()
            blocked = true
            detail = "已达到单次 60 秒上限。松开 Siri 键后可继续。"
        } else if let lastFrame, now - lastFrame >= 2 {
            finish()
            blocked = true
            detail = "音频传输中断。松开 Siri 键后重试。"
        }
        if phase == .draining, recording == nil, !pendingAudio {
            phase = connected ? .ready : .waiting
        }
    }

    func interrupt(_ message: String) {
        let awaitingRelease = recording != nil && released == nil
        finish()
        blocked = blocked || awaitingRelease
        phase = connected ? .ready : .waiting
        detail = message
    }

    func recoverAfterWake() {
        finish()
        blocked = false
        phase = connected ? .ready : .waiting
        detail = "Mac 已唤醒，可以重新按住 Siri 键说话。"
    }

    func finish() {
        guard let recording else { return }
        self.recording = nil
        started = nil
        lastFrame = nil
        released = nil
        level = 0
        phase = connected ? .draining : .waiting
        if recording.frames > 0 {
            let issues = recording.missingFrames + recording.rejectedFrames
            detail = issues > 0 ? "本段检测到 \(issues) 个丢失或无效音频帧。" : nil
            onFinished?(recording)
        } else {
            detail = "收到 Siri 按键，但没有音频。请重新按住说话。"
        }
    }
}

// All mutable fields are confined to queue. A dispatch source timer coalesces
// work instead of enqueuing audio tasks faster than the decoder can consume.
final class VoiceCapture: @unchecked Sendable {
    struct Snapshot: Sendable {
        var phase: VoiceSession.Phase
        var level: Double
        var duration: Double
        var detail: String?
        var lastRecording: URL?
        var lastDuration: Double
        var microphoneError: Int32?
        var captureStarted: Bool
        var receivedBytes: UInt64
    }
    private let queue = DispatchQueue(label: "cn.yohoia.rimo.voice", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var descriptor: Int32 = -1
    private var parser = PacketStream()
    private var readiness = VoiceCaptureReadiness()
    private var remote: RemoteVoicePackets
    private let session = VoiceSession()
    private let output = MicrophoneOutput()
    private var lastRecording: URL?
    private var lastDuration = 0.0
    private var microphoneError: Int32?
    private var receivedBytes: UInt64 = 0
    private var error: String?
    private var saveError: String?
    private let pendingFiles = DispatchSemaphore(value: 3)
    private let fileQueue = DispatchQueue(label: "cn.yohoia.rimo.voice-files", qos: .utility)
    private var hadOutput = false
    private var lastOutput = 0.0
    private var lastPublish = 0.0
    private let publish: @Sendable (Snapshot) -> Void
    private let failed: @Sendable (String) -> Void
    private let recordingsFolder: URL?
    private let captureMarker: URL?
    private let captureIsStarted: Bool
    /// Whether the current Siri hold goes to Rimo Remote Microphone. Set by
    /// the app when Siri is pressed; segments already playing finish as they
    /// started so the audio tail is never cut.
    private var routing = true

    init(address: String, publish: @escaping @Sendable (Snapshot) -> Void,
         failed: @escaping @Sendable (String) -> Void, recordingsFolder: URL? = nil, captureMarker: URL? = nil, captureIsStarted: Bool = false) throws {
        remote = try RemoteVoicePackets(address: address)
        self.publish = publish
        self.failed = failed
        self.recordingsFolder = recordingsFolder
        self.captureMarker = captureMarker
        self.captureIsStarted = captureIsStarted
    }

    func start(descriptor: Int32) {
        queue.async { [self] in
            self.descriptor = descriptor
            output.refresh()
            output.reset()
            session.onPCM = { [weak self] pcm in
                guard let self, self.routing else { return }
                let result = self.output.push(pcm)
                self.microphoneError = result == noErr ? nil : result
                if result == noErr {
                    self.hadOutput = true
                    self.lastOutput = ProcessInfo.processInfo.systemUptime
                }
            }
            session.onFinished = { [weak self] in self?.save($0) }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(3))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop(drain: Bool, completion: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self = self else { completion(); return }
            self.timer?.cancel()
            self.timer = nil
            if drain { self.poll() }
            self.session.finish()
            self.output.reset()
            if self.descriptor >= 0 { close(self.descriptor); self.descriptor = -1 }
            self.fileQueue.async { [weak self] in
                guard let self = self else { completion(); return }
                self.queue.async { [weak self] in
                    guard let self = self else { completion(); return }
                    self.emit()
                    completion()
                }
            }
        }
    }

    func setRouting(_ value: Bool) {
        queue.async { [self] in routing = value }
    }

    func recoverAfterWake() {
        queue.async { [self] in
            session.recoverAfterWake()
            remote.resetPress()
            output.refresh()
            output.reset()
            emit()
        }
    }

    private func poll() {
        guard descriptor >= 0, error == nil else { return }
        do {
            // Bound both memory and work per timer delivery. A stalled consumer
            // backpressures the FIFO without creating a growing trace file.
            var bytes = [UInt8](repeating: 0, count: 65_536)
            for _ in 0..<16 {
                let count = read(descriptor, &bytes, bytes.count)
                if count < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    if errno == EINTR { continue }
                    throw VoiceError.message("蓝牙数据管道读取失败（\(errno)）。")
                }
                if count == 0 { break }
                receivedBytes += UInt64(count)
                for record in try parser.append(Data(bytes.prefix(count))) {
                    if let message = readiness.failure(for: record) { throw VoiceError.message(message) }
                    for event in remote.consume(record) {
                        do {
                            try session.consume(event, at: ProcessInfo.processInfo.systemUptime)
                        } catch {
                            session.interrupt(error.localizedDescription)
                        }
                        if event == .disconnected { output.reset() }
                    }
                }
            }
            let now = ProcessInfo.processInfo.systemUptime
            let started = captureIsStarted || (captureMarker.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
            if let message = readiness.failure(at: now, started: started, identified: remote.connection != nil) {
                throw VoiceError.message(message)
            }
            let pending = output.status().map { $0.pendingFrames > 0 }
                ?? (hadOutput && now - lastOutput < 0.2)
            session.tick(at: now, pendingAudio: pending)
            if now - lastPublish >= 0.1 {
                lastPublish = now
                emit()
            }
        } catch {
            self.error = error.localizedDescription
            session.interrupt(error.localizedDescription)
            output.reset()
            failed(error.localizedDescription)
        }
    }

    func shutdown() {
        queue.sync {
            timer?.cancel()
            timer = nil
            session.finish()
            output.reset()
            if descriptor >= 0 { close(descriptor); descriptor = -1 }
        }
        fileQueue.sync {}
    }

    /// Audio goes only to the virtual microphone. Segments are written to disk
    /// only when a caller (tests, diagnostics) supplies a folder.
    private func save(_ recording: VoiceRecording) {
        guard let recordingsFolder else { return }
        guard pendingFiles.wait(timeout: .now()) == .success else {
            saveError = "录音保存队列已满，本段未保存。请检查磁盘。"
            return
        }
        let archive = recording.archive
        fileQueue.async { [self] in
            defer { pendingFiles.signal() }
            do {
                let folder = recordingsFolder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let name = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let url = folder.appendingPathComponent("A2540-\(name)-\(UUID().uuidString.prefix(6)).wav")
                try archive.save(to: url)
                queue.async { [self] in
                    lastRecording = url
                    lastDuration = archive.duration
                    saveError = nil
                    emit()
                }
            } catch {
                let message = "保存录音失败：\(error.localizedDescription)"
                queue.async { [self] in saveError = message; emit() }
            }
        }
    }

    private func emit() {
        publish(Snapshot(phase: session.phase, level: session.level, duration: session.duration,
                         detail: error ?? saveError ?? session.detail, lastRecording: lastRecording,
                         lastDuration: lastDuration, microphoneError: microphoneError,
                         captureStarted: captureIsStarted || (captureMarker.map { FileManager.default.fileExists(atPath: $0.path) } ?? false),
                         receivedBytes: receivedBytes))
    }
}
