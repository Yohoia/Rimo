// Read-only test for whether public CoreBluetooth can see the remote's voice service.
import AppKit
import CoreBluetooth

@main
private final class GATTDiscovery: NSObject, NSApplicationDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let voice = CBUUID(string: "8341F2B4-C013-4F04-8197-C4CDB42E26DC")
    private let hid = CBUUID(string: "1812")
    private let target = Bundle.main.object(forInfoDictionaryKey: "RimoRemoteName") as? String
    private let text = NSTextField(wrappingLabelWithString: "正在检查蓝牙权限…")
    private var window: NSWindow?
    private var manager: CBCentralManager?
    private var timeout: Timer?
    private var peripheral: CBPeripheral?
    private var finished = false

    static func main() {
        let app = NSApplication.shared
        let delegate = GATTDiscovery()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 130),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Rimo · A2540 蓝牙语音诊断"
        window.isReleasedWhenClosed = false
        text.frame = NSRect(x: 22, y: 25, width: 416, height: 80)
        window.contentView?.addSubview(text)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        manager = CBCentralManager(delegate: self, queue: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !finished else { return }
        switch central.state {
        case .poweredOn:
            if let target, let match = central.retrieveConnectedPeripherals(withServices: [voice, hid])
                .first(where: { $0.name == target }) {
                checkServices(of: match, using: central)
                return
            }
            if target == nil && !central.retrieveConnectedPeripherals(withServices: [voice]).isEmpty {
                finish("CoreBluetooth 在系统已连接设备中找到了语音服务。")
                return
            }
            text.stringValue = "正在查找遥控器（15 秒）…"
            // With a specific target, also allow advertisements that omit the voice UUID.
            central.scanForPeripherals(withServices: target == nil ? [voice] : nil)
            timeout?.invalidate()
            timeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.finish(self.target == nil
                    ? "A2540 保持系统配对时，CoreBluetooth 没有发现语音服务。"
                    : "CoreBluetooth 的已连接设备列表和扫描都没有找到这只 A2540。")
            }
        case .unauthorized:
            finish("macOS 没有授权这个诊断工具使用蓝牙。")
        case .poweredOff:
            finish("Mac 蓝牙未开启。")
        case .unsupported:
            finish("这台 Mac 不支持 CoreBluetooth 诊断。")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !finished, self.peripheral == nil else { return }
        if let target {
            guard peripheral.name == target || advertisementData[CBAdvertisementDataLocalNameKey] as? String == target
            else { return }
            checkServices(of: peripheral, using: central)
        } else {
            finish("CoreBluetooth 扫描到了公开语音服务的设备，下一步确认它是不是 A2540。")
        }
    }

    private func checkServices(of peripheral: CBPeripheral, using central: CBCentralManager) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        timeout?.invalidate()
        text.stringValue = "找到了这只遥控器，正在读取它的语音服务列表…"
        timeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.finish("找到了这只遥控器，但没有等到语音服务查询结果。")
        }
        if peripheral.state == .connected {
            peripheral.discoverServices([voice])
        } else {
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !finished, peripheral === self.peripheral else { return }
        peripheral.discoverServices([voice])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard !finished, peripheral === self.peripheral else { return }
        finish("找到了这只遥控器，但无法打开应用侧的服务查询连接：\(error?.localizedDescription ?? "未知错误")")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !finished, peripheral === self.peripheral else { return }
        if let error {
            finish("语音服务查询失败：\(error.localizedDescription)")
        } else if peripheral.services?.contains(where: { $0.uuid == voice }) == true {
            finish("已确认这只 A2540 对应用公开蓝牙语音服务。")
        } else {
            finish("找到了这只 A2540，但它没有对应用公开蓝牙语音服务。")
        }
    }

    private func finish(_ message: String) {
        finished = true
        timeout?.invalidate()
        manager?.stopScan()
        if let peripheral { manager?.cancelPeripheralConnection(peripheral) }
        text.stringValue = message
    }
}
