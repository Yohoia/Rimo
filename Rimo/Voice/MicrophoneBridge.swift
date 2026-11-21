import Foundation
import CoreAudio

// Each instance is confined to its owning queue. Audio publishing uses an
// independent instance from the UI's periodic device diagnostics.
final class MicrophoneOutput {
    struct Status: Sendable {
        let clients: UInt64
        let writes: UInt64
        let reads: UInt64
        let writtenFrames: UInt64
        let readFrames: UInt64
        let pendingFrames: UInt64
        let silentFrames: UInt64
    }

    private var device = AudioObjectID(kAudioObjectUnknown)
    private(set) var available = false

    func refresh() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "cn.yohoia.rimo.microphone" as CFString
        var found = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let result = withUnsafePointer(to: &uid) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), $0, &size, &found)
        }
        var pcm = property(0x7370636d)
        device = found
        available = result == noErr && found != kAudioObjectUnknown && AudioObjectHasProperty(found, &pcm)
    }

    @discardableResult
    func reset() -> OSStatus { send(Data()) }

    func push(_ pcm: [Int16]) -> OSStatus {
        let floats = pcm.map { Float($0) / 32768 }
        return send(floats.withUnsafeBytes { Data($0) })
    }

    func status() -> Status? {
        guard available else { return nil }
        var address = property(0x73737461) // 'ssta'
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var reference: Unmanaged<CFData>?
        var size = UInt32(MemoryLayout<Unmanaged<CFData>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &reference) == noErr,
              let reference else { return nil }
        let bytes = reference.takeRetainedValue() as Data
        guard bytes.count == 64 else { return nil }
        let values = bytes.withUnsafeBytes { raw in
            (0..<8).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self) }
        }
        guard values[0] == 1 else { return nil }
        return Status(clients: values[1], writes: values[2], reads: values[3], writtenFrames: values[4],
                      readFrames: values[5], pendingFrames: values[6], silentFrames: values[7])
    }

    private func send(_ data: Data) -> OSStatus {
        if !available { refresh() }
        guard available else { return kAudioHardwareBadDeviceError }
        var address = property(0x7370636d)
        let referenceData = data as CFData
        // Use passRetained to safely transfer ownership to Core Audio
        var reference = Unmanaged.passRetained(referenceData)
        let result = AudioObjectSetPropertyData(device, &address, 0, nil,
            UInt32(MemoryLayout<Unmanaged<CFData>>.size), &reference)
        // Balance the retain with release after the call completes
        reference.release()
        if result != noErr {
            // Rebind for the next block after coreaudiod or the device restarts.
            // Retrying this block could duplicate a successful partial delivery.
            available = false
        }
        return result
    }

    private func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
