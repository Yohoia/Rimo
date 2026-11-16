import AppKit
import Foundation

@main
struct RemoteConfigurationTest {
    static func main() throws {
        let returnKey = KeyboardShortcut(option: KeyboardShortcut.navigationKeys[0], flags: [])
        let command = SystemShortcut(id: UUID(), name: "Example (with parentheses)")
        let globalAction = RemoteAction.keyboard(returnKey)
        let sceneAction = RemoteAction.shortcut(command)

        var configuration = RemoteConfiguration()
        configuration.global[.playPause] = globalAction
        configuration.scenes = [AppSceneMapping(id: "sample.player", name: "Player", buttons: configuration.global)]
        configuration.scenes[0].buttons[.playPause] = sceneAction

        precondition(configuration.action(for: .playPause, in: "sample.player") == globalAction)
        configuration.automatic = true
        precondition(configuration.action(for: .playPause, in: "sample.player") == sceneAction)
        precondition(configuration.action(for: .playPause, in: "sample.other") == globalAction)
        precondition(configuration.action(for: .playPause, in: nil) == globalAction)

        configuration.scenes[0].buttons.setEnabled(false, for: .playPause)
        precondition(configuration.action(for: .playPause, in: "sample.player") == nil)
        precondition(configuration.action(for: .playPause, in: "sample.other") == globalAction)

        let decoded = try JSONDecoder().decode(RemoteConfiguration.self, from: JSONEncoder().encode(configuration))
        precondition(decoded == configuration)
        configuration.scenes[0].enabled = false
        precondition(configuration.action(for: .playPause, in: "sample.player") == globalAction)
        print("Scene selection, disabled button behavior and persistence passed.")
    }
}
