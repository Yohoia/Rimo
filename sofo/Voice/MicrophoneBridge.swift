import AppKit
import Combine
import CoreAudio

@MainActor
final class MicrophoneBridge: ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var installed = false
    @Published private(set) var installing = false
    @Published private(set) var message: String?
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var task: Process?
    private var errors: Pipe?
    private var timer: Timer?
    private let pcmSelector: AudioObjectPropertySelector = 0x7370636d // 'spcm'
    private let driverPath = "/Library/Audio/Plug-Ins/HAL/SofoMicrophone.driver"

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        installed = FileManager.default.fileExists(atPath: driverPath)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "cn.yohoia.sofo.microphone" as CFString
        var output = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let result = withUnsafePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), pointer, &size, &output)
        }
        if result == noErr && output != kAudioObjectUnknown {
            var custom = property()
            device = output
            available = AudioObjectHasProperty(output, &custom)
        } else { device = AudioObjectID(kAudioObjectUnknown); available = false }
    }

    func reset() { send(Data()) }

    func push(_ pcm: [Int16]) {
        guard available, !pcm.isEmpty else { return }
        // The custom HAL property marshals CFData using CoreAudio's built-in IPC.
        let floats = pcm.map { Float($0) / 32768 }
        send(floats.withUnsafeBytes { Data($0) })
    }

    private func send(_ data: Data) {
        guard available else { return }
        var address = property()
        var reference = data as CFData
        let result = AudioObjectSetPropertyData(device, &address, 0, nil,
            UInt32(MemoryLayout<CFData>.size), &reference)
        if result != noErr {
            message = "麦克风音频传输失败（\(result)），请停止后重新启用收音。"
            available = false
        }
    }

    func install() {
        guard !installed, !installing, let resources = Bundle.main.resourceURL else { return }
        let source = resources.appendingPathComponent("SofoMicrophone.driver")
        guard FileManager.default.fileExists(atPath: source.path) else {
            message = "缺少麦克风驱动，请重新构建 sofo。"
            return
        }
        let command = ["/bin/bash", resources.appendingPathComponent("install-microphone.sh").path, source.path]
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges with prompt \"sofo 将安装系统麦克风，让其他应用使用遥控器的声音。\""]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            Task { @MainActor in self?.installationEnded(code: code) }
        }
        task = process; errors = pipe; installing = true; message = nil
        do { try process.run() }
        catch { task = nil; errors = nil; installing = false; message = error.localizedDescription }
    }

    private func installationEnded(code: Int32) {
        let error = errors.flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) } ?? ""
        task = nil; errors = nil; installing = false
        refresh()
        if code == 0 {
            message = available ? "系统麦克风已就绪。请在使用声音的 App 中选择 sofo Remote Microphone。" : "驱动已安装。请重新启动 Mac，让系统加载麦克风。"
        } else if error.contains("-128") { message = "已取消安装。遥控器录音仍可正常使用。" }
        else { message = "安装失败：" + String(error.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)) }
    }

    func shutdown() {
        reset()
        timer?.invalidate(); timer = nil
    }

    private func property() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: pcmSelector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
