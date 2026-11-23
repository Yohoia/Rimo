import Foundation
import IOKit.hid
import IOKit.ps
import Darwin

@MainActor
final class HIDMonitor {
    enum Status: Equatable {
        case stopped, waiting, connected, failed(Int32)
    }

    struct DeviceInformation: Equatable {
        let manufacturer: String?
        let vendorID: Int?
        let productID: Int?
    }

    var onBattery: ((Int) -> Void)?
    var onStatus: ((Status) -> Void)?
    var onButton: ((RemoteButton, RemoteButtonEdge) -> Void)?
    var onDeviceRemoved: (() -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onButtonReport: ((String) -> Void)?
    var onRemoteAddress: ((String) -> Void)?

    private var manager: IOHIDManager?
    private var devices: Set<UInt> = []
    private var buttons = RemoteButtonState()
    private var deviceBuffers: [UInt: UnsafeMutablePointer<UInt8>] = [:]
    private var deviceRefs: [UInt: IOHIDDevice] = [:]

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

    static func batteryPercentage() -> Int? {
        if let percent = accessoryBatteryPercentage() { return percent }
        let probe = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(probe, A2540Input.vendorIDs.map {
            [kIOHIDVendorIDKey: $0, kIOHIDProductIDKey: A2540Input.productID]
        } as CFArray)
        let devices = IOHIDManagerCopyDevices(probe) as? Set<IOHIDDevice> ?? []
        let values = Set(devices.compactMap { device -> Int? in
            guard let value = IOHIDDeviceGetProperty(device, "BatteryPercent" as CFString) as? Int,
                  (0...100).contains(value) else { return nil }
            return value
        })
        // Avoid showing another remote's level when multiple physical devices are present.
        return values.count == 1 ? values.first : nil
    }

    static func deviceInformation(address: String) -> DeviceInformation? {
        let probe = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(probe, A2540Input.vendorIDs.map {
            [kIOHIDVendorIDKey: $0, kIOHIDProductIDKey: A2540Input.productID]
        } as CFArray)
        let devices = IOHIDManagerCopyDevices(probe) as? Set<IOHIDDevice> ?? []
        let matching = devices.filter { device in
            let value = IOHIDDeviceGetProperty(device, "DeviceAddress" as CFString) as? String
                ?? IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
            return value?.replacingOccurrences(of: "-", with: ":").lowercased() == address
        }
        guard !matching.isEmpty else { return nil }
        func uniqueString(_ key: String) -> String? {
            let values = Set(matching.compactMap {
                (IOHIDDeviceGetProperty($0, key as CFString) as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty })
            return values.count == 1 ? values.first : nil
        }
        func uniqueNumber(_ key: String) -> Int? {
            let values = Set(matching.compactMap { IOHIDDeviceGetProperty($0, key as CFString) as? Int })
            return values.count == 1 ? values.first : nil
        }
        return DeviceInformation(manufacturer: uniqueString(kIOHIDManufacturerKey),
                                 vendorID: uniqueNumber(kIOHIDVendorIDKey),
                                 productID: uniqueNumber(kIOHIDProductIDKey))
    }

    // The default IOPS snapshot excludes Bluetooth accessory sources. Request all
    // sources through the optional system export, retaining HID as a fallback.
    private static func accessoryBatteryPercentage() -> Int? {
        guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "IOPSCopyPowerSourcesByType") else { return nil }
        typealias CopySources = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        let copySources = unsafeBitCast(symbol, to: CopySources.self)
        guard let snapshot = copySources(0)?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let addresses = connectedRemoteAddresses()
        guard addresses.count == 1 else { return nil }
        let levels = sources.compactMap { source -> Int? in
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info["Type"] as? String == "Accessory Source",
                  let vendor = info["Vendor ID"] as? Int, A2540Input.vendorIDs.contains(vendor),
                  info["Product ID"] as? Int == A2540Input.productID,
                  let current = info["Current Capacity"] as? Int,
                  let maximum = info["Max Capacity"] as? Int,
                  maximum > 0, (0...maximum).contains(current),
                  info["Is Present"] as? Bool != false else { return nil }
            return Int((Double(current) / Double(maximum) * 100).rounded())
        }
        return levels.count == 1 ? levels.first : nil
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
        // Copy device references to avoid concurrent modification during iteration
        let devicesToCleanup = Array(deviceRefs)
        // Unregister callbacks before deallocating buffers to prevent use-after-free
        for (deviceID, device) in devicesToCleanup {
            if let buffer = deviceBuffers[deviceID] {
                IOHIDDeviceRegisterInputReportCallback(device, buffer, 0, nil, nil)
            }
        }
        IOHIDManagerClose(manager, 0)
        self.manager = nil
        // Clean up allocated buffers after callbacks are unregistered
        for buffer in deviceBuffers.values {
            buffer.deallocate()
        }
        deviceBuffers.removeAll()
        deviceRefs.removeAll()
        devices.removeAll()
        buttons.reset()
        onStatus?(.stopped)
    }

    private func id(of device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func attach(_ device: IOHIDDevice) {
        let deviceID = id(of: device)
        guard devices.insert(deviceID).inserted else { return }
        deviceRefs[deviceID] = device
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        if let address = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String,
           (try? RemoteVoicePackets(address: address)) != nil {
            onRemoteAddress?(address)
        }

        // Enable report callback for this device - allocate buffer and track it for cleanup
        let reportSize = 256
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
        deviceBuffers[deviceID] = buffer
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
        // Unregister callback before deallocating buffer
        // This is called on MainActor so the unregister is synchronous
        if let buffer = deviceBuffers[deviceID] {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 0, nil, nil)
            // Add a small delay to ensure IOKit completes callback dispatch
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        // Clean up buffer and device reference
        if let buffer = deviceBuffers.removeValue(forKey: deviceID) {
            buffer.deallocate()
        }
        deviceRefs.removeValue(forKey: deviceID)
        onDeviceRemoved?()
        onStatus?(devices.isEmpty ? .waiting : .connected)
    }

    private func read(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let deviceID = id(of: device)
        guard devices.contains(deviceID) else { return }

        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        // Generic Device Controls / Battery Strength, scaled by the declared logical range.
        if page == 0x06 && usage == 0x20 {
            let low = IOHIDElementGetLogicalMin(element), high = IOHIDElementGetLogicalMax(element)
            let raw = IOHIDValueGetIntegerValue(value)
            if high > low, (low...high).contains(raw) {
                onBattery?(Int((Double(raw) - Double(low)) / (Double(high) - Double(low)) * 100))
            }
            return
        }
        guard page == 0x01 || page == 0x0c else { return }
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        onDiagnostic?(String(format: "HID %02X/%02X · %@", page, usage, pressed ? "按下" : "松开"))
        let reportID = IOHIDElementGetReportID(element)
        guard let button = A2540Input.button(page: page, usage: usage, reportID: reportID) else { return }
        let cookie = IOHIDElementGetCookie(element)
        if let edge = buttons.update(button, pressed: pressed, from: .init(device: deviceID, cookie: cookie)) {
            onButton?(button, edge)
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
