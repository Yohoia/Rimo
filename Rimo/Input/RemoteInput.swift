enum RemoteButton: String, CaseIterable, Identifiable {
    case up, down, left, right, select, back, menu, home, playPause, mute, volumeUp, volumeDown, power, siri

    var id: Self { self }

    var title: String {
        switch self {
        case .up: "上"
        case .down: "下"
        case .left: "左"
        case .right: "右"
        case .select: "确认"
        case .back: "返回"
        case .menu: "菜单"
        case .home: "电视 / 主屏幕"
        case .playPause: "播放 / 暂停"
        case .mute: "静音"
        case .volumeUp: "音量加"
        case .volumeDown: "音量减"
        case .power: "电源"
        case .siri: "Siri（侧键）"
        }
    }
}

enum A2540Input {
    static let modelName = "A2540"
    static let vendorIDs = [0x004c, 0x05ac]
    static let productID = 0x0314
    static let buttonReportID: UInt32 = 0xfb

    static func button(page: UInt32, usage: UInt32, reportID: UInt32) -> RemoteButton? {
        switch (page, usage) {
        case (0x01, 0x86): .back
        // A2540 uses the Microphone usage for both the side button and the audio interface.
        case (0x0c, 0x04) where reportID == buttonReportID: .siri
        case (0x0c, 0x30): .power
        case (0x0c, 0x42): .up
        case (0x0c, 0x43): .down
        case (0x0c, 0x44): .left
        case (0x0c, 0x45): .right
        case (0x0c, 0x60): .home
        case (0x0c, 0x80): .select
        case (0x0c, 0xcd): .playPause
        case (0x0c, 0xe2): .mute
        case (0x0c, 0xe9): .volumeUp
        case (0x0c, 0xea): .volumeDown
        default: nil
        }
    }
}

enum RemoteTrigger: String, CaseIterable, Identifiable {
    case single, doublePress, hold

    var id: Self { self }
    var title: String {
        switch self {
        case .single: "单击"
        case .doublePress: "双击"
        case .hold: "长按"
        }
    }

    func mappingKey(for button: RemoteButton) -> String {
        self == .single ? button.rawValue : "\(rawValue).\(button.rawValue)"
    }
}

enum RemoteButtonEdge: Equatable {
    case pressed, released
}

// Merge duplicate HID sources into one press and release per physical key.
struct RemoteButtonState {
    struct Source: Hashable {
        let device: UInt
        let cookie: UInt32
    }

    private var heldBySource: [Source: RemoteButton] = [:]

    mutating func update(_ button: RemoteButton, pressed: Bool, from source: Source) -> RemoteButtonEdge? {
        let alreadyHeld = heldBySource.values.contains(button)
        if pressed {
            heldBySource[source] = button
            return alreadyHeld ? nil : .pressed
        }
        guard heldBySource.removeValue(forKey: source) == button,
              !heldBySource.values.contains(button) else { return nil }
        return .released
    }

    mutating func remove(device: UInt) {
        heldBySource = heldBySource.filter { $0.key.device != device }
    }

    mutating func reset() {
        heldBySource.removeAll()
    }
}

/// Recognizes a single sequence on one button using monotonic time.
struct RemotePressSequence {
    static let doubleInterval = 0.26
    static let holdInterval = 0.50

    let recognizesDouble: Bool
    let recognizesHold: Bool

    private enum Phase {
        case idle, down(second: Bool, holdAt: Double), waiting(until: Double), consumed
    }

    private var phase: Phase = .idle

    init(recognizesDouble: Bool, recognizesHold: Bool) {
        self.recognizesDouble = recognizesDouble
        self.recognizesHold = recognizesHold
    }

    var deadline: Double? {
        switch phase {
        case .down(_, let holdAt): holdAt
        case .waiting(let until): until
        case .idle, .consumed: nil
        }
    }

    var isIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    mutating func advance(to time: Double) -> RemoteTrigger? {
        guard let deadline, time >= deadline else { return nil }
        switch phase {
        case .down:
            phase = .consumed
            return recognizesHold ? .hold : .single
        case .waiting:
            phase = .idle
            return .single
        case .idle, .consumed:
            return nil
        }
    }

    mutating func receive(_ edge: RemoteButtonEdge, at time: Double) -> [RemoteTrigger] {
        var result = advance(to: time).map { [$0] } ?? []
        switch (edge, phase) {
        case (.pressed, .idle):
            if recognizesDouble || recognizesHold {
                phase = .down(second: false, holdAt: time + Self.holdInterval)
            } else {
                phase = .consumed
                result.append(.single)
            }
        case (.pressed, .waiting):
            phase = .down(second: true, holdAt: time + Self.holdInterval)
        case (.released, .down(let second, _)):
            if second || !recognizesDouble {
                phase = .idle
                result.append(second ? .doublePress : .single)
            } else {
                phase = .waiting(until: time + Self.doubleInterval)
            }
        case (.released, .consumed):
            phase = .idle
        default:
            break
        }
        return result
    }
}
