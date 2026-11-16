import Foundation
import IOKit.hid

@MainActor
final class HIDMonitor {
    enum Status: Equatable {
        case stopped, waiting, connected, failed(Int32)
    }

    var onStatus: ((Status) -> Void)?
    var onButton: ((RemoteButton) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onButtonReport: ((String) -> Void)?
    var onRemoteAddress: ((String) -> Void)?

    private var manager: IOHIDManager?
    private var devices: Set<UInt> = []
    private var buttons = RemoteButtonState()

    // Enumerating registry properties needs no input-monitoring permission.
    // Opening the manager for event callbacks does; keep these paths separate.
    static func connectedRemoteAddresses() -> Set<String> {
        let probe = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(probe, A2540Input.vendorIDs.map {
            [kIOHIDVendorIDKey: $0, kIOHIDProductIDKey: A2540Input.productID]
        } as CFArray)
        let devices = IOHIDManagerCopyDevices(probe) as? Set<IOHIDDevice> ?? []
        return Set(devices.compactMap { device in
            let value = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
                ?? IOHIDDeviceGetProperty(device, "DeviceAddress" as CFString) as? String
            guard let value, (try? RemoteVoicePackets(address: value)) != nil else { return nil }
            return value.replacingOccurrences(of: "-", with: ":").lowercased()
        })
    }

    func start() {
        guard manager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let criteria = A2540Input.vendorIDs.map { vendor in
            [kIOHIDVendorIDKey: vendor, kIOHIDProductIDKey: A2540Input.productID]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, criteria as CFArray)
        onDiagnostic?("HIDManager 开始搜索 A2540（VID: \(A2540Input.vendorIDs.map { String(format: "%04X", $0) }.joined(separator: " ")) PID: \(String(format: "%04X", A2540Input.productID))）")

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().attach(device)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().detach(device)
            }
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard let context, result == kIOReturnSuccess else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().read(value)
            }
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, _, reportID, bytes, length in
            guard let context, let sender, result == kIOReturnSuccess, length > 0 else { return }
            let deviceID = UInt(bitPattern: sender)
            let sample = Array(UnsafeBufferPointer(start: bytes, count: min(length, 16)))
            MainActor.assumeIsolated {
                Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
                    .readReport(reportID, sample, length: length, device: deviceID)
            }
        }, context)

        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            onStatus?(.failed(result))
            onDiagnostic?("HIDManager 打开失败，错误码：\(result)")
            return
        }

        self.manager = manager
        onStatus?(.waiting)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        if let existing = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            onDiagnostic?("发现 \(existing.count) 个已连接的 HID 设备")
            for device in existing { attach(device) }
        } else {
            onDiagnostic?("未发现已连接的 HID 设备，等待新连接...")
        }
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, 0)
        self.manager = nil
        devices.removeAll()
        buttons.reset()
        onStatus?(.stopped)
    }

    private func id(of device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func attach(_ device: IOHIDDevice) {
        guard devices.insert(id(of: device)).inserted else { return }
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        if let address = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String,
           (try? RemoteVoicePackets(address: address)) != nil {
            onRemoteAddress?(address)
        }

        // Enable report callback for this device
        let reportSize = 256
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, reportSize, { context, result, sender, _, reportID, bytes, length in
            guard let context, let sender, result == kIOReturnSuccess else { return }
            let deviceID = UInt(bitPattern: sender)
            let sample = Array(UnsafeBufferPointer(start: bytes, count: min(length, 16)))
            MainActor.assumeIsolated {
                Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
                    .readReport(reportID, sample, length: length, device: deviceID)
            }
        }, context)

        onDiagnostic?(String(format: "A2540 已发现：VID %04X · PID %04X", vendor, product))
        onStatus?(.connected)
    }

    private func detach(_ device: IOHIDDevice) {
        let deviceID = id(of: device)
        devices.remove(deviceID)
        buttons.remove(device: deviceID)
        onStatus?(devices.isEmpty ? .waiting : .connected)
    }

    private func read(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let deviceID = id(of: device)
        guard devices.contains(deviceID) else { return }

        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard page == 0x01 || page == 0x0c else { return }
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        onDiagnostic?(String(format: "HID %02X/%02X · %@", page, usage, pressed ? "按下" : "松开"))
        let reportID = IOHIDElementGetReportID(element)
        guard let button = A2540Input.button(page: page, usage: usage, reportID: reportID) else { return }
        let cookie = IOHIDElementGetCookie(element)
        if buttons.update(button, pressed: pressed, from: .init(device: deviceID, cookie: cookie)) {
            onButton?(button)
        }
    }

    private func readReport(_ reportID: UInt32, _ sample: [UInt8], length: Int, device: UInt) {
        guard devices.contains(device) else { return }
        let hex = sample.map { String(format: "%02X", $0) }.joined(separator: " ")
        onButtonReport?(String(format: "报文 ID 0x%02X · %d 字节 · %@", reportID, length, hex))
        onDiagnostic?(String(format: "收到报文：ID=0x%02X 长度=%d", reportID, length))

        // Observe raw reports without using unverified bytes to trigger system actions.
        // Enable decoding here only after capturing the A2540's on-device report layout.
    }
}
