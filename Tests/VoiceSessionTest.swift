import Foundation

@_silgen_name("opus_encoder_create")
private func encoderCreate(_ rate: Int32, _ channels: Int32, _ application: Int32,
                           _ error: UnsafeMutablePointer<Int32>) -> OpaquePointer?
@_silgen_name("opus_encoder_destroy")
private func encoderDestroy(_ encoder: OpaquePointer)
@_silgen_name("opus_encode")
private func encode(_ encoder: OpaquePointer, _ samples: UnsafePointer<Int16>, _ count: Int32,
                    _ bytes: UnsafeMutablePointer<UInt8>, _ capacity: Int32) -> Int32

@main
struct VoiceSessionTest {
    static func main() throws {
        var error: Int32 = 0
        let encoder = encoderCreate(48_000, 1, 2048, &error)!
        defer { encoderDestroy(encoder) }
        let samples = (0..<960).map { Int16(sin(Double($0) * 0.06) * 2000) }
        var bytes = [UInt8](repeating: 0, count: 4000)
        let size = encode(encoder, samples, 960, &bytes, 4000)
        precondition(size > 0 && size < 256)
        func payload(_ sequence: UInt16) -> [UInt8] {
            [0, 0, UInt8(sequence & 255), UInt8(sequence >> 8), UInt8(size)] + bytes.prefix(Int(size))
        }
        let session = VoiceSession()
        var outputSamples = 0
        var segments: [VoiceRecording.Archive] = []
        session.onPCM = { outputSamples += $0.count }
        session.onFinished = { segments.append($0.archive) }
        try session.consume(.connected, at: 0)
        try session.consume(.button(true), at: 1)
        try session.consume(.audio(payload(0)), at: 1.01)
        try session.consume(.audio(payload(0)), at: 1.02)
        precondition(outputSamples == 960, "Duplicate frame was published")
        try session.consume(.audio(payload(2)), at: 1.03)
        precondition(outputSamples == 2880, "Lost frame did not preserve the PCM timeline")
        precondition(session.recording?.concealedFrames == 1)
        try session.consume(.button(false), at: 1.04)
        precondition(session.phase == .draining)
        try session.consume(.audio(payload(3)), at: 1.05)
        try session.consume(.end, at: 1.06)
        session.tick(at: 1.07, pendingAudio: true)
        precondition(session.phase == .draining, "Tail output was reported as finished too early")
        session.tick(at: 1.2, pendingAudio: false)
        precondition(session.phase == .ready && segments.count == 1)
        precondition(segments[0].samples.count == 3840, "Tail frame was lost")
        try session.consume(.button(true), at: 2)
        try session.consume(.audio(payload(0)), at: 2.01)
        try session.consume(.button(false), at: 2.02)
        session.tick(at: 2.3, pendingAudio: false)
        precondition(segments.count == 2 && segments[1].samples.count == 960)
        // A missing release is bounded, and late audio cannot resume the segment.
        try session.consume(.button(true), at: 3)
        try session.consume(.audio(payload(0)), at: 3.01)
        session.tick(at: 5.1, pendingAudio: false)
        try session.consume(.audio(payload(1)), at: 5.2)
        precondition(session.recording == nil && segments.count == 3)
        try session.consume(.button(false), at: 5.3)
        try session.consume(.button(true), at: 6)
        try session.consume(.audio(payload(0)), at: 6.01)
        try session.consume(.disconnected, at: 6.02)
        precondition(session.phase == .waiting && segments.count == 4)
        try session.consume(.connected, at: 7)
        try session.consume(.button(true), at: 7.1)
        try session.consume(.audio(payload(0)), at: 7.2)
        try session.consume(.end, at: 7.3)
        // Device end before physical release cannot leave a new recording open.
        try session.consume(.button(true), at: 7.4)
        precondition(session.recording == nil)
        try session.consume(.button(false), at: 7.5)
        try session.consume(.button(true), at: 8)
        session.interrupt("wake")
        session.interrupt("stop")
        precondition(session.recording == nil && segments.count == 5)
        try session.consume(.button(false), at: 8.1)
        session.interrupt("idle wake")
        try session.consume(.button(true), at: 9)
        precondition(session.recording != nil, "Idle wake swallowed the first press")
        session.recoverAfterWake()
        try session.consume(.button(true), at: 10)
        precondition(session.recording != nil, "Wake recovery did not allow a new segment")
        session.finish()
        print("PASS: real Opus; duplicate suppression; loss concealment; tail drain; consecutive segments; lost release; disconnect; reconnect; early end; repeated cancellation")
    }
}
