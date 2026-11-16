// Local experiment: capture one A2540 push-to-talk session through IOKit.
// Not part of the sofo application target.
import Darwin
import Foundation
import IOKit.hid

private func property(_ device: IOHIDDevice, _ key: String) -> Int? {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int
}

private func isAudio(_ device: IOHIDDevice) -> Bool {
    property(device, kIOHIDPrimaryUsagePageKey) == 0x0c && property(device, kIOHIDPrimaryUsageKey) == 0x04
}

private final class Capture {
    var started: TimeInterval?
    var ended = false
    var disconnected = false
    var reports: [Data] = []
    var audio: IOHIDDevice?
    let enableFeature: Bool

    init(enableFeature: Bool) { self.enableFeature = enableFeature }

    func button(_ down: Bool) {
        guard !ended else { return }
        if down {
            guard started == nil else { return }
            started = ProcessInfo.processInfo.systemUptime
            print("Siri 按下，等待 A2540 音频…")
            fflush(stdout)
            if enableFeature, let audio {
                var command: UInt8 = 0xaf
                let result = IOHIDDeviceSetReport(audio, kIOHIDReportTypeFeature, 0xff, &command, 1)
                print(String(format: "音频接口 Feature 0xFF：0x%08X", UInt32(bitPattern: result)))
                fflush(stdout)
            }
        } else if started != nil {
            ended = true
            print("Siri 松开，收到 \(reports.count) 份音频接口报文。")
            fflush(stdout)
        }
    }
}

@main
private enum VoicePrototype {
    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        let check = arguments.first == "--check"
        guard check || (arguments.first != nil && arguments.first != "--enable-feature") else {
            print("Usage: capture --check | FRAME_FILE [--enable-feature]")
            exit(64)
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let criteria = [0x004c, 0x05ac].map { vendor in
            [kIOHIDVendorIDKey: vendor, kIOHIDProductIDKey: 0x0314]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, criteria as CFArray)
        let capture = Capture(enableFeature: arguments.contains("--enable-feature"))
        let context = Unmanaged.passUnretained(capture).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard let context, result == kIOReturnSuccess else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == 0x0c, IOHIDElementGetUsage(element) == 0x04,
                  IOHIDElementGetReportID(element) == 0xfb else { return }
            Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue().button(IOHIDValueGetIntegerValue(value) != 0)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context, isAudio(device) else { return }
            let capture = Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue()
            capture.disconnected = true
            capture.ended = true
        }, context)
        guard let loop = CFRunLoopGetCurrent() else { exit(2) }
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            print(String(format: "无法打开 A2540 HID：0x%08X；请检查输入监控。", UInt32(bitPattern: result)))
            exit(2)
        }
        let mode = CFRunLoopMode.commonModes.rawValue
        IOHIDManagerScheduleWithRunLoop(manager, loop, mode)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let audioDevices = devices.filter(isAudio)
        print("A2540 HID 接口：\(devices.count)；音频接口：\(audioDevices.count)。")
        guard audioDevices.count == 1, let audio = audioDevices.first else { exit(2) }
        if check { return }

        capture.audio = audio
        let size = property(audio, kIOHIDMaxInputReportSizeKey) ?? 0
        guard (6...4096).contains(size) else { print("音频接口的报文长度无效。"); exit(2) }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, loop, mode)
            IOHIDManagerClose(manager, 0)
            // The registered callback and its buffer are used only on this run loop.
            buffer.deallocate()
        }
        IOHIDDeviceRegisterInputReportCallback(audio, buffer, size, { context, result, _, _, id, bytes, length in
            guard let context, result == kIOReturnSuccess, id == 0xff, length > 0 else { return }
            let capture = Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue()
            guard capture.started != nil, !capture.ended else { return }
            capture.reports.append(Data(bytes: bytes, count: length))
        }, context)
        print("已就绪。请按住 Siri 侧键说话，松开结束（最长 12 秒）。")
        fflush(stdout)

        let deadline = ProcessInfo.processInfo.systemUptime + 120
        while !capture.ended {
            let now = ProcessInfo.processInfo.systemUptime
            let stop = capture.started.map { $0 + 12 } ?? deadline
            guard now < stop else { break }
            CFRunLoopRunInMode(.defaultMode, min(0.15, stop - now), false)
        }
        guard !capture.disconnected else { print("A2540 已断开，未保存录音。"); exit(3) }
        guard capture.started != nil else { print("未收到 Siri 键按下，未录音。"); exit(3) }
        guard !capture.reports.isEmpty else { print("已检测到 Siri 键，但音频接口没有送出报文。"); exit(4) }
        let lines = capture.reports.map { $0.map { String(format: "%02x", $0) }.joined() }
        try (lines.joined(separator: "\n") + "\n").write(toFile: String(arguments.first!), atomically: true, encoding: .utf8)
    }
}
