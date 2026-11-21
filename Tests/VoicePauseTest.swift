import Combine
import Darwin
import Foundation

// Replace only the privileged XPC boundary. Exercise the real controller while
// authorization and stop replies are delayed, without installing or recording.
@MainActor
final class VoiceHelperClient: ObservableObject {
    static let shared = VoiceHelperClient()
    enum Installation: Equatable { case missing, outdated, installed, unavailable(String) }
    @Published var installation = Installation.installed
    var deploying = false
    var onCaptureEnded: ((String) -> Void)?
    var starts = 0
    var stops = 0
    var readiness: [CheckedContinuation<Void, Error>] = []
    var stopping: [CheckedContinuation<Void, Never>] = []
    func refreshStatus() {}
    func ensureReady(allowDeploy: Bool) async throws {
        starts += 1
        try await withCheckedThrowingContinuation { readiness.append($0) }
    }
    func stopCapture() async {
        stops += 1
        await withCheckedContinuation { stopping.append($0) }
    }
    func perform(_ operation: String) async throws -> [String: Bool] { ["configured": true] }
    func startCapture() async throws -> Int32 { fatalError("A cancelled startup opened the audio pipe") }
    func redeploy() async throws {}
    func uninstall() async throws {}
    func shutdown() {}
}

@main
struct VoicePauseTest {
    @MainActor
    static func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !predicate() {
            precondition(Date() < deadline, "Controller lifecycle timed out")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor
    static func main() async throws {
        let helper = VoiceHelperClient.shared
        let voice = VoiceController()
        voice.setAddress("00:11:22:33:44:55")
        voice.setWanted(true)
        try await wait { helper.starts == 1 }
        voice.setWanted(false)
        try await wait { helper.stops == 1 }
        precondition(voice.state == .stopping)
        voice.siriPressed(routingAudio: true)
        precondition(!voice.wanted && helper.starts == 1)
        // Resume arrives while the prior capture is still stopping.
        voice.setWanted(true)
        helper.readiness.removeFirst().resume(throwing: NSError(domain: "Cancelled startup", code: 1))
        for _ in 0..<20 { await Task.yield() }
        precondition(voice.state == .stopping, "A cancelled startup overwrote the stopping state")
        helper.stopping.removeFirst().resume()
        try await wait { helper.starts == 2 }
        precondition(voice.wanted && voice.enabled, "Quick pause/resume failed to restart capture")
        voice.setWanted(false)
        try await wait { helper.stops == 2 }
        helper.stopping.removeFirst().resume()
        try await wait { !voice.enabled }
        helper.readiness.removeFirst().resume()
        for _ in 0..<20 { await Task.yield() }
        precondition(!voice.wanted && !voice.enabled && voice.state == .off)
        voice.siriPressed(routingAudio: true)
        precondition(helper.starts == 2)

        // Stop may finish before the cancelled authorization reply arrives.
        voice.setWanted(true)
        try await wait { helper.starts == 3 }
        helper.deploying = true
        voice.setWanted(false)
        try await wait { helper.stops == 3 }
        voice.setWanted(true)
        helper.stopping.removeFirst().resume()
        try await wait { !voice.enabled }
        helper.deploying = false
        helper.readiness.removeFirst().resume()
        try await wait { helper.starts == 4 }
        voice.setWanted(false)
        try await wait { helper.stops == 4 }
        helper.stopping.removeFirst().resume()
        try await wait { !voice.enabled }
        helper.readiness.removeFirst().resume()
        for _ in 0..<20 { await Task.yield() }

        // A direct stop used by repair must not be mistaken for a quick resume.
        voice.setWanted(true)
        try await wait { helper.starts == 5 }
        voice.stop()
        try await wait { helper.stops == 5 }
        helper.stopping.removeFirst().resume()
        try await wait { !voice.enabled }
        helper.readiness.removeFirst().resume()
        for _ in 0..<20 { await Task.yield() }
        precondition(helper.starts == 5 && !voice.enabled)
        voice.shutdown()
        print("PASS: real voice controller; delayed authorization; cancelled startup; paused Siri press; quick resume during stop; final shutdown")
    }
}
