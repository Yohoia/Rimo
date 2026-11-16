import Foundation

@main
struct VoiceReplay {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("Usage: voice-replay CAPTURE PEER OUTPUT.wav")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let peer = CommandLine.arguments[2]
        var reference = PacketStream()
        let records = try reference.append(data)
        // Replay every possible framing boundary in varying chunk lengths.
        for size in [1, 7, 12, 13, 64, 1024] {
            var stream = PacketStream()
            var count = 0
            for start in stride(from: 0, to: data.count, by: size) {
                count += try stream.append(data.subdata(in: start..<min(start + size, data.count))).count
            }
            precondition(count == records.count, "Chunked framing lost records")
        }
        var remote = try RemoteVoicePackets(address: peer)
        var foreign = try RemoteVoicePackets(address: "00:11:22:33:44:55")
        let recording = try VoiceRecording()
        var downs = 0, ups = 0, ends = 0, frames = 0
        for record in records {
            precondition(foreign.consume(record).isEmpty, "Unrelated device accepted")
            for event in remote.consume(record) {
                switch event {
                case .button(true): downs += 1
                case .button(false): ups += 1
                case .end: ends += 1
                case .audio(let bytes):
                    frames += 1
                    try recording.append(bytes)
                    try recording.append(bytes) // Duplicates must not duplicate audio.
                default: break
                }
            }
        }
        precondition(downs == 1 && ups == 1 && ends == 1, "Siri press/release/end not identified")
        precondition(frames == 221 && recording.frames == 221, "Real recording lost frames")
        precondition(recording.missingFrames == 0 && recording.rejectedFrames == 0)
        precondition(abs(recording.duration - 4.42) < 0.001)
        try recording.save(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        // A disconnect invalidates learned handles and rejects stale fragments.
        let h = remote.connection!
        let disconnected = TraceRecord(time: 0, kind: 1, bytes: [5, 4, 0, UInt8(h & 255), UInt8(h >> 8), 0x13])
        precondition(remote.consume(disconnected) == [.disconnected])
        precondition(remote.connection == nil)
        for record in records where record.kind == 3 { precondition(remote.consume(record).isEmpty) }
        print("PASS: \(records.count) records; identified remote; Siri press/release; 221 audio frames; 4.42s WAV; chunk boundaries; duplicate frames; unrelated device filtering; disconnect reset")
    }
}
