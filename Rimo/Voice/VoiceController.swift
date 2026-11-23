import AppKit
import Combine
import Darwin

@MainActor
final class VoiceController: ObservableObject {
    let helper = VoiceHelperClient.shared
    enum State: Equatable {
        case off, authorizing, waiting, ready, recording, draining, stopping, failed(String)
        var title: String {
            switch self {
            case .off: "遥控器语音已关闭"
            case .authorizing: "正在启动遥控器语音…"
            case .waiting: "等待遥控器语音连接…"
            case .ready: "已就绪，按住 Siri 键说话"
            case .recording: "正在收音，松开 Siri 键结束"
            case .draining: "正在输出尾音…"
            case .stopping: "正在停止…"
            case .failed(let message): message
            }
        }
    }
    @Published private(set) var state: State = .off
    @Published private(set) var level = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var detail: String?
    /// Whether a Siri-key voice action is mapped. Capture follows it
    /// automatically across launches, reconnects, sleep and failures.
    private(set) var wanted = false
    /// The user has accepted or declined component installation.
    @Published private(set) var setupDecided: Bool
    /// Capture is running or starting.
    var enabled: Bool { activation != nil || capture != nil }

    private var address: String?
    private var activation: Task<Void, Never>?
    private var capture: VoiceCapture?
    private var wakeObserver: AnyCancellable?
    @Published private(set) var receivedBytes: UInt64 = 0
    @Published private(set) var microphoneError: Int32?
    private var generation = UUID()
    private var stopping = false
    private var captureFailure: String?
    /// Guards processEnded against double-invocation (helper callback + capture failure arriving together).
    private var processingEnded = false
    private var helperChanges: AnyCancellable?
    private var retry: Task<Void, Never>?
    private var failures = 0
    private var restartWhenStopped = false
    private let defaults = UserDefaults.standard
    private static let decidedKey = "voice-setup-decided-v1"

    init() {
        setupDecided = defaults.bool(forKey: Self.decidedKey)
        helperChanges = helper.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // Earlier builds already installed components with the user's consent.
        if helper.installation == .installed || helper.installation == .outdated { markDecided() }
        helper.onCaptureEnded = { [weak self] message in
            guard let self, self.enabled else { return }
            if !message.isEmpty { self.captureFailure = message }
            self.processEnded(token: self.generation)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let capture = self.capture { capture.recoverAfterWake() }
                    else { self.resume() }
                }
            }
    }

    /// Shown once in first-run setup (or once after upgrading) to ask for the
    /// single administrator authorization.
    var needsOnboarding: Bool { !setupDecided && helper.installation == .missing }

    var installed: Bool { helper.installation == .installed || helper.installation == .outdated }

    func setAddress(_ value: String?) {
        // Keep the known address through disconnects so HCI reconnection events
        // can identify the same remote without accepting unrelated BLE traffic.
        guard let value, value != address else { return }
        address = value
        if enabled { restartWhenStopped = wanted; stop() }
        else { resume() }
    }

    /// Follows the Siri key mapping: mapping a voice action starts capture,
    /// mapping anything else stops it. Never prompts by itself on launch.
    func setWanted(_ value: Bool) {
        guard value != wanted else { return }
        wanted = value
        if value { failures = 0; resume() }
        else {
            retry?.cancel(); retry = nil
            restartWhenStopped = false
            if enabled { stop() } else { state = .off; detail = nil }
        }
    }

    /// Installs components with one administrator prompt (first-run setup,
    /// or the user choosing a voice action before installing).
    func install() async throws {
        try await helper.ensureReady(allowDeploy: true)
        markDecided()
        resume()
    }

    func declineSetup() { markDecided() }

    /// Menu bar repair: retry capture, redeploying components if needed.
    func repair() {
        retry?.cancel(); retry = nil
        failures = 0
        Task { [weak self] in
            guard let self else { return }
            await halt()
            do { try await helper.redeploy() } catch { state = .failed(error.localizedDescription); return }
            resume()
        }
    }

    /// Like RemotePilot, a Siri press revives a voice channel that has stopped.
    func siriPressed(routingAudio: Bool) {
        guard wanted, !stopping else { return }
        capture?.setRouting(routingAudio)
        guard routingAudio, wanted, !enabled, retry == nil else { return }
        resume()
    }

    func uninstall() async throws {
        retry?.cancel(); retry = nil
        await halt()
        try await helper.uninstall()
        state = .off
        detail = nil
    }

    private func markDecided() {
        setupDecided = true
        defaults.set(true, forKey: Self.decidedKey)
    }

    /// Automatic start. Updates after a Rimo upgrade show the system password
    /// prompt by themselves (as RemotePilot's helper does); first installation
    /// waits for the setup page.
    private func resume() {
        guard wanted else { return }
        if stopping { restartWhenStopped = true; return }
        guard !enabled else { return }
        if helper.deploying { restartWhenStopped = true; return }
        restartWhenStopped = false
        helper.refreshStatus()
        switch helper.installation {
        case .installed: failures = 0; start(interactive: false)
        case .outdated: start(interactive: true)
        case .missing: state = .off
        case .unavailable(let reason): state = .failed(reason)
        }
    }

    private func halt() async {
        restartWhenStopped = false
        stop()
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while enabled, ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func scheduleRetry() {
        guard wanted, retry == nil else { return }
        failures += 1
        // Persistent failures (e.g. Bluetooth refusing live traces) stop after
        // three attempts; a Siri press, reconnect or wake tries again.
        let delays = [2.0, 5.0, 15.0]
        guard failures <= delays.count else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delays[(self?.failures ?? 1) - 1]))
            guard let self, !Task.isCancelled else { return }
            self.retry = nil
            if self.wanted, !self.enabled { self.start(interactive: false) }
        }
    }

    private func start(interactive: Bool) {
        guard wanted, !enabled, !helper.deploying else { return }
        guard let address else { state = .waiting; detail = "连接 A2540 后自动开始。"; return }
        let token = UUID()
        generation = token
        stopping = false
        captureFailure = nil
        detail = nil
        state = .authorizing
        activation = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == token { activation = nil }
                // An authorization reply can arrive after pause/stop finished.
                // A quick resume must not be lost while that reply was pending.
                if Task.isCancelled, restartWhenStopped, wanted, !enabled, !stopping { resume() }
            }
            do {
                // Installs components with one administrator prompt when needed.
                try await helper.ensureReady(allowDeploy: interactive)
                guard generation == token, !Task.isCancelled else { return }
                // macOS updates can reset Bluetooth diagnostics; reapply silently.
                if try await helper.perform("status")["configured"] != true {
                    _ = try await helper.perform("configure")
                }
                guard generation == token, !Task.isCancelled else { return }
                let worker = try VoiceCapture(address: address, publish: { [weak self] snapshot in
                    Task { @MainActor in self?.update(snapshot, token: token) }
                }, failed: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == token, !self.stopping else { return }
                        self.captureFailure = message
                        self.processEnded(token: token)
                    }
                }, captureIsStarted: true)
                capture = worker
                let descriptor = try await helper.startCapture()
                guard generation == token, !Task.isCancelled else {
                    close(descriptor)
                    await helper.stopCapture()
                    return
                }
                receivedBytes = 0
                microphoneError = nil
                worker.start(descriptor: descriptor)
                state = .waiting
            } catch {
                guard generation == token, !Task.isCancelled, !stopping, wanted else { return }
                capture?.shutdown()
                capture = nil
                state = .failed(error.localizedDescription)
                // A cancelled update is not retried until the next launch or
                // Siri press, so the password prompt never loops.
                if helper.installation == .installed { scheduleRetry() }
            }
        }
    }

    func stop() {
        guard enabled, !stopping else { return }
        stopping = true
        state = .stopping
        activation?.cancel()
        // Shut down the local pipe and clear queued PCM immediately rather
        // than continuing to output audio while the helper acknowledges stop.
        capture?.setRouting(false)
        capture?.stop(drain: false, completion: {})
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            await helper.stopCapture()
            guard generation == token else { return }
            // Process ended after helper cleanup is complete to avoid race with shutdown()
            processEnded(token: token)
        }
    }

    func shutdown() {
        activation?.cancel()
        activation = nil
        retry?.cancel()
        retry = nil
        stopping = true
        processingEnded = true  // Prevent processEnded from running during shutdown
        capture?.shutdown()
        capture = nil
        helper.shutdown()
    }

    private func update(_ snapshot: VoiceCapture.Snapshot, token: UUID) {
        guard generation == token else { return }
        guard !stopping else { return }
        if receivedBytes == 0 && snapshot.receivedBytes == 0 && !snapshot.captureStarted { return }
        receivedBytes = snapshot.receivedBytes
        level = snapshot.level
        duration = snapshot.duration
        detail = snapshot.detail
        microphoneError = snapshot.microphoneError
        switch snapshot.phase {
        case .waiting: state = .waiting
        case .ready: state = .ready; failures = 0
        case .recording: state = .recording
        case .draining: state = .draining
        }
    }

    private func processEnded(token: UUID) {
        guard generation == token else { return }
        guard !processingEnded else { return }
        processingEnded = true
        let completion: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                let wasStopping = self.stopping
                self.capture?.shutdown()
                self.capture = nil
                self.activation?.cancel()
                self.activation = nil
                self.generation = UUID()
                self.stopping = false
                self.processingEnded = false
                self.level = 0
                if let failure = self.captureFailure { self.state = .failed(failure) }
                else if wasStopping { self.state = .off }
                else { self.state = .failed("蓝牙采集已结束，正在自动恢复…") }
                if !wasStopping {
                    // Make sure the root capture process is gone before retrying.
                    Task { await self.helper.stopCapture() }
                    self.scheduleRetry()
                } else if self.restartWhenStopped {
                    self.restartWhenStopped = false
                    self.resume()
                }
            }
        }
        if let capture { capture.stop(drain: !stopping, completion: completion) }
        else { completion() }
    }

}
