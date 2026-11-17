import AppKit
import Combine
import IOKit.hid

@MainActor
final class RimoModel: ObservableObject {
    @Published private(set) var status: HIDMonitor.Status = .stopped
    @Published private(set) var isRemoteConnected = false
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var canListen = false
    @Published private(set) var canPost = false
    @Published private(set) var lastButton: RemoteButton?
    @Published private(set) var diagnostic: String?
    @Published private(set) var buttonReport: String?
    @Published private(set) var observedButtons: Set<RemoteButton> = []
    @Published private(set) var configurationError: String?
    @Published private(set) var actionError: String?
    @Published private(set) var paused = false
    @Published private(set) var scrollMode = RemoteScrollMode()
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
    private var pendingPresses: [RemoteButton: PendingPress] = [:]

    private var heldOutputs: [RemoteButton: KeyboardShortcut] = [:]

    private struct PendingPress {
        let appPID: pid_t?
        let actions: [RemoteTrigger: RemoteAction]
        var sequence: RemotePressSequence
        var timer: Task<Void, Never>?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Import existing mappings once when upgrading from the former bundle ID.
        // Keep these legacy identifiers so renaming the app does not reset settings.
        if defaults === UserDefaults.standard,
           defaults.object(forKey: storageKey) == nil,
           defaults.object(forKey: "keyboard-mappings-v1") == nil,
           let legacy = defaults.persistentDomain(forName: "cn.yohoia.sofo") {
            if let data = legacy[storageKey] as? Data {
                defaults.set(data, forKey: storageKey)
            } else if let data = legacy["keyboard-mappings-v1"] as? Data {
                defaults.set(data, forKey: "keyboard-mappings-v1")
            }
        }
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
            .sink { [weak self] _ in
                guard let self else { return }
                let app = NSWorkspace.shared.frontmostApplication
                if app?.processIdentifier != self.frontmostApp?.processIdentifier { self.cancelPendingPresses() }
                self.frontmostApp = app
            }

        hid.onStatus = { [weak self] status in
            self?.status = status
            if status != .connected {
                self?.cancelPendingPresses()
                self?.scrollMode.reset()
                self?.lastButton = nil
                self?.diagnostic = nil
                self?.buttonReport = nil
            }
        }
        hid.onBattery = { [weak self] percent in self?.batteryPercent = percent }
        hid.onDiagnostic = { [weak self] message in self?.diagnostic = message }
        hid.onButtonReport = { [weak self] report in self?.buttonReport = report }
        hid.onButton = { [weak self] button, edge in self?.handle(button, edge: edge) }
        hid.onDeviceRemoved = { [weak self] in
            self?.cancelPendingPresses()
            self?.scrollMode.reset()
        }
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
        if addresses.count != 1 { batteryPercent = nil }
        else if let percent = HIDMonitor.batteryPercentage() { batteryPercent = percent }
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
        cancelPendingPresses()
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
        sceneID.flatMap(scene)?.resolved(global: configuration.global) ?? configuration.global
    }

    @discardableResult
    func setAction(_ action: RemoteAction?, for button: RemoteButton, trigger: RemoteTrigger = .single,
                   sceneID: String? = nil) -> Bool {
        guard action?.isAssignable(to: button) != false else { return false }
        return updateMappings(button, trigger: trigger, sceneID: sceneID) { $0[button, trigger] = action }
    }

    func setActionEnabled(_ enabled: Bool, for button: RemoteButton, trigger: RemoteTrigger = .single, sceneID: String? = nil) {
        updateMappings(button, trigger: trigger, sceneID: sceneID) { $0.setEnabled(enabled, for: button, trigger: trigger) }
    }

    func followGlobal(_ button: RemoteButton, trigger: RemoteTrigger = .single, sceneID: String) {
        updateConfiguration {
            guard let index = $0.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
            $0.scenes[index].followGlobal(button, trigger: trigger)
        }
    }

    func setAutomaticScenes(_ enabled: Bool) {
        updateConfiguration { $0.automatic = enabled }
    }

    @discardableResult
    func addScene(id: String, name: String) -> Bool {
        guard scene(id) == nil else { return false }
        return updateConfiguration { $0.scenes.append(AppSceneMapping(id: id, name: name, buttons: $0.global)) }
    }

    func applyPreset(_ preset: ScenePreset, id: String, name: String) -> Bool {
        updateConfiguration { $0.apply(preset, to: id, name: name) }
    }

    func setSceneEnabled(_ enabled: Bool, id: String) {
        updateConfiguration {
            if let index = $0.scenes.firstIndex(where: { $0.id == id }) { $0.scenes[index].enabled = enabled }
        }
    }

    func removeScene(id: String) {
        updateConfiguration { $0.scenes.removeAll { $0.id == id } }
    }

    @discardableResult
    private func updateMappings(_ button: RemoteButton, trigger: RemoteTrigger, sceneID: String?,
                                edit: (inout ButtonMappings) -> Void) -> Bool {
        if let sceneID, scene(sceneID) == nil { return false }
        return updateConfiguration {
            if let sceneID {
                let global = $0.global
                if let index = $0.scenes.firstIndex(where: { $0.id == sceneID }) {
                    $0.scenes[index].edit(button, trigger: trigger, global: global, edit)
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
            cancelPendingPresses()
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
        scrollMode.reset()
        cancelPendingPresses()
    }

    func toggleScrollMode() {
        cancelPendingPresses()
        scrollMode.toggle()
    }

    func startRecording(_ button: RemoteButton) {
        recording = button
        cancelPendingPresses()
    }

    func cancelRecording() {
        recording = nil
    }

    private func handle(_ button: RemoteButton, edge: RemoteButtonEdge) {
        if edge == .released, let key = heldOutputs.removeValue(forKey: button) {
            _ = key.post(pressed: false)
        }
        if edge == .pressed {
            lastButton = button
            observedButtons.insert(button)
        }

        let app = NSWorkspace.shared.frontmostApplication
        var press = pendingPresses.removeValue(forKey: button)
        press?.timer?.cancel()
        guard canDispatch(button) else { return }
        if let scroll = scrollMode.scroll(for: button) {
            if edge == .pressed { dispatch(.scroll(scroll)) }
            return
        }

        if press?.appPID != app?.processIdentifier { press = nil }

        if press == nil {
            guard edge == .pressed else { return }
            let single = configuration.action(for: button, in: app?.bundleIdentifier)
            if case .keyboard(let key) = single, key.holdsUntilRelease == true {
                dispatch(.keyboard(key), heldBy: button)
                return
            }
            let double = configuration.action(for: button, trigger: .doublePress, in: app?.bundleIdentifier)
            let hold = configuration.action(for: button, trigger: .hold, in: app?.bundleIdentifier)
            guard double != nil || hold != nil else {
                if let single { dispatch(single, heldBy: button) }
                return
            }
            let actions: [RemoteTrigger: RemoteAction] = [.single: single, .doublePress: double, .hold: hold]
                .compactMapValues { $0 }
            press = PendingPress(appPID: app?.processIdentifier, actions: actions,
                                 sequence: .init(recognizesDouble: double != nil, recognizesHold: hold != nil))
        }
        guard var press else { return }
        for trigger in press.sequence.receive(edge, at: ProcessInfo.processInfo.systemUptime) {
            if let action = press.actions[trigger] {
                dispatch(action, heldBy: edge == .pressed ? button : nil)
                if action == .system(.toggleScrollMode) { return }
            }
        }
        track(press, for: button)
    }

    private func track(_ press: PendingPress, for button: RemoteButton) {
        guard !press.sequence.isIdle else { return }
        var press = press
        press.timer = nil
        if let deadline = press.sequence.deadline {
            let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            press.timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                if !Task.isCancelled { self?.finishDeadline(for: button) }
            }
        }
        pendingPresses[button] = press
    }

    private func finishDeadline(for button: RemoteButton) {
        guard var press = pendingPresses.removeValue(forKey: button), canDispatch(button),
              press.appPID == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        if let trigger = press.sequence.advance(to: ProcessInfo.processInfo.systemUptime),
           let action = press.actions[trigger] {
            dispatch(action, heldBy: trigger == .hold ? button : nil)
            if action == .system(.toggleScrollMode) { return }
        }
        track(press, for: button)
    }

    private func canDispatch(_ button: RemoteButton) -> Bool {
        !paused && recording == nil && !isSettingsFocused() && !(button == .siri && voice.enabled)
    }

    private func cancelPendingPresses() {
        for press in pendingPresses.values { press.timer?.cancel() }
        pendingPresses.removeAll()
        for key in heldOutputs.values { _ = key.post(pressed: false) }
        heldOutputs.removeAll()
    }

    private func dispatch(_ action: RemoteAction, heldBy button: RemoteButton? = nil) {
        actionError = nil
        if action == .system(.toggleScrollMode) {
            toggleScrollMode()
            return
        }
        if case .shortcut(let shortcut) = action {
            runShortcut(shortcut)
            return
        }
        if let button, case .keyboard(let key) = action, key.holdsUntilRelease == true {
            if key.post(pressed: true) { heldOutputs[button] = key }
            else { actionError = "无法发送按键，请检查辅助功能权限。" }
            return
        }
        do { try ActionOutput.perform(action) }
        catch { actionError = error.localizedDescription; canPost = CGPreflightPostEventAccess() }
    }
}
