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

// Some buttons may appear on multiple HID interfaces. Emit once until every
// source for that button is released or removed.
struct RemoteButtonState {
    struct Source: Hashable {
        let device: UInt
        let cookie: UInt32
    }

    private var heldBySource: [Source: RemoteButton] = [:]

    mutating func update(_ button: RemoteButton, pressed: Bool, from source: Source) -> Bool {
        let alreadyHeld = heldBySource.values.contains(button)
        heldBySource[source] = pressed ? button : nil
        return pressed && !alreadyHeld
    }

    mutating func remove(device: UInt) {
        heldBySource = heldBySource.filter { $0.key.device != device }
    }

    mutating func reset() {
        heldBySource.removeAll()
    }
}
