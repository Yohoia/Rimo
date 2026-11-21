import Foundation

// Shared wire contract. Paths, commands and process identifiers are never accepted.
@objc(RimoVoiceHelperProtocol)
protocol VoiceHelperProtocol {
    func handshake(reply: @escaping (Int) -> Void)
    func perform(_ operation: String, reply: @escaping (Data?, String?) -> Void)
    func startCapture(_ token: String, reply: @escaping (FileHandle?, String?) -> Void)
    func stopCapture(reply: @escaping () -> Void)
}

@objc(RimoVoiceClientProtocol)
protocol VoiceClientProtocol {
    func captureEnded(_ token: String, message: String)
}

enum VoiceHelperContract {
    static let version = 2
    // Installed by deploy-voice.sh as a system LaunchDaemon.
    static let label = "cn.yohoia.rimo.voice-service"
}
