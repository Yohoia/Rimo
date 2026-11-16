import AppKit
import Combine
import IOKit.hid

@MainActor
final class SofoModel: ObservableObject {
    @Published private(set) var status: HIDMonitor.Status = .stopped
    @Published private(set) var isRemoteConnected = false
    @Published private(set) var canListen = false
    @Published private(set) var canPost = false
    @Published private(set) var lastButton: RemoteButton?
    @Published private(set) var diagnostic: String?
    @Published private(set) var buttonReport: String?
    @Published private(set) var observedButtons: Set<RemoteButton> = []
    @Published private(set) var configurationError: String?
    @Published private(set) var paused = false
    @Published private(set) var recording: RemoteButton?
    @Published private(set) var configuration = RemoteConfiguration()
    @Published private(set) var frontmostApp = NSWorkspace.shared.frontmostApplication
    @Published private(set) var systemShortcuts: [SystemShortcut] = []
    @Published private(set) var loadingShortcuts = false
    @Published private(set) var shortcutListError: String?
    @Published private(set) var runningShortcuts: Set<UUID> = []
    @Published private(set) var shortcutFeedback: String?
    var isSettingsFocused: () -> Bool = { false }

    private let hid = HIDMonitor()
    let voice = VoiceController()
    private var voiceChanges: AnyCancellable?
    private var connectionTimer: Timer?
    private let defaults: UserDefaults
    private let storageKey = "remote-configuration-v2"
    private var workspaceChanges: AnyCancellable?
    private var loadedShortcuts = false
    private var configurationReadFailed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let data = defaults.data(forKey: storageKey) {
                configuration = try JSONDecoder().decode(RemoteConfiguration.self, from: data)
            } else if let data = defaults.data(forKey: "keyboard-mappings-v1") {
                let old = try JSONDecoder().decode([String: KeyboardShortcut].self, from: data)
                configuration.global.actions = old.mapValues(RemoteAction.keyboard)
            }
        } catch {
            configurationReadFailed = true
            configurationError = "无法读取已保存的映射。已有配置未被覆盖。"
        }

        workspaceChanges = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in self?.frontmostApp = NSWorkspace.shared.frontmostApplication }

        hid.onStatus = { [weak self] status in
            self?.status = status
            if status != .connected {
                self?.lastButton = nil
                self?.diagnostic = nil
                self?.buttonReport = nil
            }
        }
        hid.onDiagnostic = { [weak self] message in self?.diagnostic = message }
        hid.onButtonReport = { [weak self] report in self?.buttonReport = report }
        hid.onButton = { [weak self] button in self?.handle(button) }
        voiceChanges = voice.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        refresh()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshConnection() }
        }
    }

    var statusTitle: String {
        if isRemoteConnected { return "A2540 已连接" }
        return "等待 A2540 连接"
    }

    var inputStatusTitle: String {
        switch status {
        case .connected: "A2540 已连接"
        case .waiting: "等待 A2540 连接"
        case .stopped: canListen ? "监听未启动" : "等待输入监控授权"
        case .failed: "无法读取遥控器"
        }
    }

    func refresh() {
        canListen = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        canPost = CGPreflightPostEventAccess()
        refreshConnection()

        if canListen {
            hid.start()
        } else {
            hid.stop()
        }
    }

    private func refreshConnection() {
        let addresses = HIDMonitor.connectedRemoteAddresses()
        isRemoteConnected = !addresses.isEmpty
        if addresses.count == 1 { voice.setAddress(addresses.first) }
    }

    func requestInputAccess() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    func requestOutputAccess() {
        _ = CGRequestPostEventAccess()
        refresh()
    }

    func stop() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        voice.shutdown()
        hid.stop()
    }

    func retry() {
        hid.stop()
        refresh()
    }

    var activeScene: AppSceneMapping? {
        configuration.scene(for: frontmostApp?.bundleIdentifier)
    }

    func scene(_ id: String) -> AppSceneMapping? { configuration.scenes.first { $0.id == id } }

    func mappings(sceneID: String? = nil) -> ButtonMappings {
        sceneID.flatMap(scene)?.buttons ?? configuration.global
    }

    func setAction(_ action: RemoteAction?, for button: RemoteButton, sceneID: String? = nil) {
        updateMappings(sceneID: sceneID) { $0[button] = action }
    }

    func setActionEnabled(_ enabled: Bool, for button: RemoteButton, sceneID: String? = nil) {
        updateMappings(sceneID: sceneID) { $0.setEnabled(enabled, for: button) }
    }

    func setAutomaticScenes(_ enabled: Bool) {
        updateConfiguration { $0.automatic = enabled }
    }

    @discardableResult
    func addScene(id: String, name: String) -> Bool {
        guard scene(id) == nil else { return false }
        return updateConfiguration { $0.scenes.append(AppSceneMapping(id: id, name: name, buttons: $0.global)) }
    }

    func setSceneEnabled(_ enabled: Bool, id: String) {
        updateConfiguration {
            if let index = $0.scenes.firstIndex(where: { $0.id == id }) { $0.scenes[index].enabled = enabled }
        }
    }

    func removeScene(id: String) {
        updateConfiguration { $0.scenes.removeAll { $0.id == id } }
    }

    private func updateMappings(sceneID: String?, edit: (inout ButtonMappings) -> Void) {
        updateConfiguration {
            if let sceneID {
                if let index = $0.scenes.firstIndex(where: { $0.id == sceneID }) {
                    edit(&$0.scenes[index].buttons)
                }
            } else {
                edit(&$0.global)
            }
        }
    }

    @discardableResult
    private func updateConfiguration(_ edit: (inout RemoteConfiguration) -> Void) -> Bool {
        guard !configurationReadFailed else { return false }
        var next = configuration
        edit(&next)
        do {
            defaults.set(try JSONEncoder().encode(next), forKey: storageKey)
            configuration = next
            configurationError = nil
            return true
        } catch {
            configurationError = "未能保存映射。"
            return false
        }
    }

    func loadShortcuts(force: Bool = false) {
        guard !loadingShortcuts, force || !loadedShortcuts else { return }
        loadingShortcuts = true
        shortcutListError = nil
        Task { [weak self] in
            defer { self?.loadingShortcuts = false }
            do {
                let shortcuts = try await ShortcutsCLI.list()
                self?.systemShortcuts = shortcuts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self?.loadedShortcuts = true
            } catch {
                self?.shortcutListError = "无法读取快捷指令：\(error.localizedDescription)"
            }
        }
    }

    func runShortcut(_ shortcut: SystemShortcut) {
        guard runningShortcuts.insert(shortcut.id).inserted else { return }
        shortcutFeedback = "正在运行「\(shortcut.name)」…"
        Task { [weak self] in
            defer { self?.runningShortcuts.remove(shortcut.id) }
            do {
                try await ShortcutsCLI.run(shortcut)
                self?.shortcutFeedback = "已运行「\(shortcut.name)」。"
            } catch {
                self?.shortcutFeedback = "无法运行「\(shortcut.name)」：\(error.localizedDescription)"
            }
        }
    }

    func togglePaused() {
        paused.toggle()
    }

    func startRecording(_ button: RemoteButton) {
        recording = button
    }

    func cancelRecording() {
        recording = nil
    }

    private func handle(_ button: RemoteButton) {
        lastButton = button
        observedButtons.insert(button)
        if button == .siri && voice.enabled { return }
        guard !paused, recording == nil, !isSettingsFocused(),
              let action = configuration.action(for: button, in: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        else { return }
        switch action {
        case .keyboard(let shortcut):
            if !shortcut.post() { canPost = CGPreflightPostEventAccess() }
        case .shortcut(let shortcut):
            runShortcut(shortcut)
        }
    }
}
