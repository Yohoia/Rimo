import Foundation

private final class ReplyBox: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var data: Data?
    var message: String?
}

@main
struct VoiceHelperTest {
    static func main() throws {
        precondition(CommandLine.arguments.count == 2)
        // Mirror the root-owned layout written by deploy-voice.sh.
        let bundle = URL(fileURLWithPath: CommandLine.arguments[1])
        let service = FileManager.default.temporaryDirectory.appendingPathComponent("Rimo-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: service, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: service) }
        try FileManager.default.copyItem(at: bundle.appendingPathComponent("Contents/Resources/voice-environment"),
                                         to: service.appendingPathComponent("voice-environment"))
        do {
            _ = try ServiceInstallation(directory: service)
            preconditionFailure("Service without a client requirement accepted")
        } catch {}
        try Data(#"identifier "cn.yohoia.rimo""#.utf8).write(to: service.appendingPathComponent("client-requirement"))
        let application = try ServiceInstallation(directory: service)
        precondition(application.requirement == #"identifier "cn.yohoia.rimo""#)
        let server = VoiceHelperServer(application: application)
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        let session = VoiceHelperSession(server: server, connection: connection)
        var version = 0
        session.handshake { version = $0 }
        precondition(version == VoiceHelperContract.version)
        let status = ReplyBox()
        session.perform("status") { data, message in
            status.data = data
            status.message = message
            status.semaphore.signal()
        }
        precondition(status.semaphore.wait(timeout: .now() + 5) == .success)
        precondition(status.message == nil)
        let result = try JSONSerialization.jsonObject(with: status.data!) as! [String: Bool]
        precondition(result["configured"] != nil)
        let rejected = ReplyBox()
        session.perform("/bin/sh -c anything") { data, message in
            rejected.data = data
            rejected.message = message
            rejected.semaphore.signal()
        }
        precondition(rejected.semaphore.wait(timeout: .now() + 5) == .success)
        precondition(rejected.data == nil && rejected.message != nil)
        session.disconnect()
        let disconnected = ReplyBox()
        session.perform("status") { data, message in
            disconnected.data = data
            disconnected.message = message
            disconnected.semaphore.signal()
        }
        precondition(disconnected.semaphore.wait(timeout: .now() + 5) == .success)
        precondition(disconnected.data == nil && disconnected.message != nil)
        print("PASS: deployed service layout; missing client requirement rejected; protocol handshake; real status request; arbitrary command rejected; disconnected session rejected")
    }
}
