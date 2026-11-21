import Foundation
import Darwin

private final class CaptureResults: @unchecked Sendable {
    let condition = NSCondition()
    var bytes: UInt64 = 0
    var saved: URL?
    var failure: String?
    var stopped = false

    func update(_ snapshot: VoiceCapture.Snapshot) {
        condition.lock()
        bytes = snapshot.receivedBytes
        saved = snapshot.lastRecording ?? saved
        condition.broadcast()
        condition.unlock()
    }

    func wait(until predicate: () -> Bool) {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(5)
        while !predicate() {
            precondition(condition.wait(until: deadline), "Capture worker timed out")
        }
        precondition(failure == nil, "Capture worker failed")
    }
}

@main
struct VoiceCaptureTest {
    static func main() throws {
        precondition(CommandLine.arguments.count == 2, "Pass a locally captured A2540 trace")
        let trace = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        var parser = PacketStream()
        let records = try parser.append(trace)
        let metadata = records.first { $0.kind == 0xfd && $0.bytes.count >= 4 && $0.bytes[0] == 1 }!.bytes
        let offset = 4 + Int(metadata[3])
        let peer = metadata[offset..<(offset + 6)].reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Rimo-capture-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fifo = folder.appendingPathComponent("trace.pipe").path
        precondition(mkfifo(fifo, 0o600) == 0)
        let reader = open(fifo, O_RDWR | O_NONBLOCK | O_CLOEXEC)
        precondition(reader >= 0)
        let results = CaptureResults()
        let capture = try VoiceCapture(address: peer, publish: { results.update($0) }, failed: { message in
            results.condition.lock()
            results.failure = message
            results.condition.broadcast()
            results.condition.unlock()
        }, recordingsFolder: folder)
        capture.start(descriptor: reader)
        let writer = open(fifo, O_WRONLY | O_CLOEXEC)
        precondition(writer >= 0)
        try trace.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = write(writer, raw.baseAddress!.advanced(by: offset), min(97, raw.count - offset))
                guard count > 0 else { throw VoiceError.message("FIFO write failed") }
                offset += count
            }
        }
        close(writer)
        results.wait { results.bytes == UInt64(trace.count) }
        capture.stop(drain: true) {
            results.condition.lock()
            results.stopped = true
            results.condition.broadcast()
            results.condition.unlock()
        }
        results.wait { results.stopped }
        capture.shutdown()
        let wave = try Data(contentsOf: results.saved!)
        precondition(wave.count == 44 + 221 * 960 * 2)
        let recording = try VoiceRecording()
        var packets = try RemoteVoicePackets(address: peer)
        for record in records {
            for event in packets.consume(record) {
                if case .audio(let payload) = event { try recording.append(payload) }
            }
        }
        let reference = folder.appendingPathComponent("reference.wav")
        try recording.save(to: reference)
        let referenceWave = try Data(contentsOf: reference)
        precondition(wave == referenceWave)
        print("PASS: real A2540 trace through fragmented FIFO; background decode; asynchronous WAV save; stop waits for files; byte-identical audio")
    }
}
