import Foundation

struct TraceRecord {
    let time: Double
    let kind: UInt8
    let bytes: [UInt8]
}

enum VoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

// Incremental PacketLogger framing. A read can end anywhere, including in the header.
struct PacketStream {
    private var pending = [UInt8]()
    private var littleEndian: Bool?

    mutating func append(_ data: Data) throws -> [TraceRecord] {
        pending.append(contentsOf: data)
        var offset = 0
        var result = [TraceRecord]()
        while pending.count - offset >= 12 {
            if littleEndian == nil {
                let orders = [false, true].filter { little in
                    let size = word(offset, little: little)
                    return (9...65544).contains(size) && word(offset + 8, little: little) < 1_000_000
                }
                guard orders.count == 1 else { throw VoiceError.message("无法识别蓝牙数据格式。请停止后重新启用收音。") }
                littleEndian = orders[0]
            }
            let little = littleEndian!
            let size = Int(word(offset, little: little))
            let micros = word(offset + 8, little: little)
            guard (9...65544).contains(size), micros < 1_000_000 else {
                throw VoiceError.message("蓝牙数据损坏。请停止后重新启用收音。")
            }
            guard pending.count - offset >= size + 4 else { break }
            result.append(TraceRecord(time: Double(word(offset + 4, little: little)) + Double(micros) / 1_000_000,
                                      kind: pending[offset + 12], bytes: Array(pending[(offset + 13)..<(offset + size + 4)])))
            offset += size + 4
        }
        if offset > 0 { pending.removeFirst(offset) }
        return result
    }

    private func word(_ offset: Int, little: Bool) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(pending[offset + $1]) << ((little ? $1 : 3 - $1) * 8) }
    }
}

struct RemoteVoicePackets {
    enum Event: Equatable {
        case connected, disconnected, button(Bool), audio([UInt8]), end
    }
    let address: [UInt8] // Bluetooth address in wire (least significant byte first) order.
    private(set) var connection: UInt16?
    private var partial: (expected: Int, data: [UInt8])?
    private var audioAttribute: UInt16?
    private var buttonAttribute: UInt16?
    private var pressed = false

    init(address: String) throws {
        let parts = address.replacingOccurrences(of: "-", with: ":").split(separator: ":")
        let bytes = parts.compactMap { $0.count == 2 ? UInt8($0, radix: 16) : nil }
        guard bytes.count == 6 else { throw VoiceError.message("未能读取遥控器蓝牙地址。请重新连接 A2540。") }
        self.address = bytes.reversed()
    }

    mutating func consume(_ record: TraceRecord) -> [Event] {
        let b = record.bytes
        // PacketLogger's initial connection metadata is present even if the remote
        // connected before capture. Type 1 = LE connection, followed by handle,
        // name length, UTF-8 name, peer address, and the CoreBluetooth identifier.
        if record.kind == 0xfd, b.count >= 4, b[0] == 1 {
            let end = 4 + Int(b[3])
            guard b.count >= end + 6, Array(b[end..<(end + 6)]) == address else { return [] }
            return connect(u16(b, 1) & 0x0fff)
        }
        if record.kind == 1, b.count >= 2, b.count == Int(b[1]) + 2 {
            if b[0] == 0x3e, b.count >= 14, [UInt8(1), 0x0a, 0x29].contains(b[2]), b[3] == 0 {
                let handle = u16(b, 4) & 0xfff
                if Array(b[8..<14]) == address { return connect(handle) }
                if connection == handle { return disconnect() }
            } else if b[0] == 5, b.count >= 6, b[2] == 0, connection == u16(b, 3) & 0xfff {
                return disconnect()
            }
            return []
        }
        guard record.kind == 3, b.count >= 4, connection == u16(b, 0) & 0xfff,
              b.count - 4 == Int(u16(b, 2)) else { return [] }
        let boundary = (u16(b, 0) >> 12) & 3
        let expected: Int
        var data: [UInt8]
        if boundary == 1 {
            guard let saved = partial else { return [] }
            expected = saved.expected
            data = saved.data + b[4...]
            partial = nil
        } else {
            partial = nil
            guard b.count >= 8, u16(b, 6) == 4 else { return [] }
            expected = Int(u16(b, 4))
            guard expected <= 4096 else { return [] }
            data = Array(b[8...])
        }
        if data.count < expected { partial = (expected, data); return [] }
        guard data.count == expected, data.count >= 3, data[0] == 0x1b else { return [] }
        let attribute = u16(data, 1)
        let payload = Array(data.dropFirst(3))
        // Learn attributes on this identified A2540 connection; never assume that
        // handles observed in one capture belong to the next connection.
        if payload == [0x20, 0], buttonAttribute == nil || buttonAttribute == attribute {
            buttonAttribute = attribute
            guard !pressed else { return [] }
            pressed = true
            return [.button(true)]
        }
        if attribute == buttonAttribute, payload == [0, 0] {
            guard pressed else { return [] }
            pressed = false
            return [.button(false)]
        }
        guard payload.count == 99 else { return [] }
        if attribute == audioAttribute, payload.allSatisfy({ $0 == 0 }) { return [.end] }
        guard pressed || audioAttribute == attribute, payload[4] > 0, payload[4] <= 94,
              payload[5] & 0xf8 == 0xb8 else { return [] }
        if audioAttribute == nil { audioAttribute = attribute }
        guard audioAttribute == attribute else { return [] }
        return [.audio(payload)]
    }

    private mutating func connect(_ handle: UInt16) -> [Event] {
        let hadConnection = connection != nil
        connection = handle
        partial = nil; audioAttribute = nil; buttonAttribute = nil; pressed = false
        return (hadConnection ? [.disconnected] : []) + [.connected]
    }

    private mutating func disconnect() -> [Event] {
        connection = nil; partial = nil; audioAttribute = nil; buttonAttribute = nil; pressed = false
        return [.disconnected]
    }

    private func u16(_ b: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(b[offset]) | UInt16(b[offset + 1]) << 8
    }
}
