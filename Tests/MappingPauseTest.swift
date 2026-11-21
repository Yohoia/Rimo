import AppKit
import Foundation

@main
struct MappingPauseTest {
    @MainActor
    static func main() throws {
        let suite = "Rimo-pause-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var configuration = RemoteConfiguration()
        let fn = RemoteAction.keyboard(KeyboardShortcut(option: .init(id: 63, title: "Fn"), flags: []))
        configuration.global[.siri] = fn
        defaults.set(try JSONEncoder().encode(configuration), forKey: "remote-configuration-v2")
        let model = RimoModel(defaults: defaults)
        defer { model.stop() }
        precondition(model.voice.wanted, "A configured Siri voice key should enable the voice chain")
        model.togglePaused()
        precondition(model.paused)
        precondition(!model.voice.wanted, "Paused mappings still request Siri audio capture")
        // Reconfiguring while paused must not restart voice capture.
        precondition(model.setAction(fn, for: .siri, trigger: .hold))
        precondition(!model.voice.wanted, "Editing a paused voice mapping re-enabled capture")
        model.voice.siriPressed(routingAudio: true)
        precondition(!model.voice.wanted && !model.voice.enabled, "Siri revived capture while paused")
        model.togglePaused()
        precondition(!model.paused && model.voice.wanted)
        // Removing the last voice mapping while paused must stay off on resume.
        model.togglePaused()
        precondition(model.setAction(nil, for: .siri, trigger: .hold))
        model.togglePaused()
        precondition(!model.voice.wanted)
        // Enabled app scenes are subject to the same pause gate.
        precondition(model.applyPreset(.reading, id: "test.reader", name: "Reader"))
        precondition(model.setAction(fn, for: .siri, sceneID: "test.reader"))
        precondition(model.voice.wanted)
        model.togglePaused()
        precondition(!model.voice.wanted)
        model.togglePaused()
        precondition(model.voice.wanted)
        print("PASS: actual model pause/resume; mapping edits while paused; Siri press while paused; removed mappings; app scenes")
    }
}
