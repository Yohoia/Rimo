import Foundation

@main
struct VoiceCaptureReadinessTest {
    static func main() {
        var check = VoiceCaptureReadiness()
        precondition(check.failure(at: 0, started: false, identified: false) == nil)
        precondition(check.failure(at: 100, started: true, identified: false) == nil)
        precondition(check.failure(at: 116, started: true, identified: false) != nil,
                     "Capture can wait forever when bluetoothd refuses live traces")
        precondition(check.failure(at: 117, started: true, identified: true) == nil)
        precondition(check.failure(for: TraceRecord(time: 0, kind: 0xfc,
            bytes: Array("Bluetooth Profile Required".utf8)))?.contains("描述文件") == true)
        print("PASS: authorization does not consume startup budget; missing live stream times out; identified remote accepted; missing profile note reported")
    }
}
