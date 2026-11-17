import Foundation

@_silgen_name("opus_decoder_create")
private func opusCreate(_ rate: Int32, _ channels: Int32, _ error: UnsafeMutablePointer<Int32>) -> OpaquePointer?
@_silgen_name("opus_decoder_destroy")
private func opusDestroy(_ decoder: OpaquePointer)
@_silgen_name("opus_decode")
private func opusDecode(_ decoder: OpaquePointer, _ bytes: UnsafePointer<UInt8>, _ length: Int32,
                        _ pcm: UnsafeMutablePointer<Int16>, _ capacity: Int32, _ fec: Int32) -> Int32

// Used on the main actor by VoiceController; also replayable in the CLI harness.
final class VoiceRecording {
    private let decoder: OpaquePointer
    private var previous: UInt16?
    private(set) var samples = [Int16]()
    private(set) var frames = 0
    private(set) var missingFrames = 0
    private(set) var rejectedFrames = 0
    var onPCM: (([Int16]) -> Void)?
    var duration: Double { Double(samples.count) / 48_000 }

    init() throws {
        var error: Int32 = 0
        guard let decoder = opusCreate(48_000, 1, &error), error == 0 else {
            throw VoiceError.message("无法启动音频解码器（\(error)）。")
        }
        self.decoder = decoder
    }

    deinit { opusDestroy(decoder) }

    @discardableResult
    func append(_ payload: [UInt8]) throws -> Double {
        guard payload.count >= 6, payload[4] > 0, Int(payload[4]) <= payload.count - 5 else {
            rejectedFrames += 1
            return 0
        }
        let sequence = UInt16(payload[2]) | UInt16(payload[3]) << 8
        if let previous {
            if sequence == previous { return 0 }
            let distance = sequence &- previous
            // Old packets must not move the decode cursor backwards.
            guard distance < 0x8000 else { return 0 }
            missingFrames += Int(distance) - 1
        }
        let packet = Array(payload[5..<(5 + Int(payload[4]))])
        var pcm = [Int16](repeating: 0, count: 5760)
        let count = packet.withUnsafeBufferPointer { bytes in
            pcm.withUnsafeMutableBufferPointer { output in
                opusDecode(decoder, bytes.baseAddress!, Int32(bytes.count), output.baseAddress!, Int32(output.count), 0)
            }
        }
        guard count > 0 else { rejectedFrames += 1; return 0 }
        // Bound a lost-release recording to one minute even if the sender misbehaves.
        guard samples.count + Int(count) <= 48_000 * 60 else {
            throw VoiceError.message("单次收音已到 60 秒上限。松开 Siri 键后可重新录音。")
        }
        previous = sequence
        frames += 1
        samples.append(contentsOf: pcm.prefix(Int(count)))
        onPCM?(Array(pcm.prefix(Int(count))))
        let rms = sqrt(pcm.prefix(Int(count)).reduce(0.0) { $0 + pow(Double($1) / 32768, 2) } / Double(count))
        return min(1, max(0, (20 * log10(max(rms, 0.00001)) + 60) / 60))
    }

    func save(to url: URL) throws {
        guard !samples.isEmpty else { throw VoiceError.message("本次未收到音频。请重新按住 Siri 键说话。") }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        func u32(_ value: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> shift) & 255)) }
        }
        let size = UInt32(samples.count * 2)
        text("RIFF"); u32(36 + size); text("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(48_000); u32(96_000); u16(2); u16(16)
        text("data"); u32(size)
        for sample in samples { u16(UInt16(bitPattern: sample)) }
        try data.write(to: url, options: [.withoutOverwriting])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
