import AppKit
import Combine
import CoreBluetooth
import IOKit.hid
import os

@MainActor
final class RimoModel: ObservableObject {
    let toasts = RimoToastCenter()
    @Published private(set) var status: HIDMonitor.Status = .stopped
    @Published private(set) var isRemoteConnected = false
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var deviceInformation: HIDMonitor.DeviceInformation?
    @Published private(set) var remoteAddress: String?
    @Published private(set) var bluetoothAuthorization = CBManagerAuthorization.notDetermined
    @Published private(set) var permissionStatusLoaded = false
    @Published private(set) var permissionOnboardingCompleted = false
    @Published private(set) var setupWelcomeCompleted = false
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
    var isSettingsFocused: () -> Bool = { false }

    private var permissionRefresh: Task<Void, Never>?
    private lazy var bluetoothRequest = BluetoothPermissionRequest { [weak self] in self?.refresh() }
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
    private var pendingReleases: [RemoteButton: (key: KeyboardShortcut, task: Task<Void, Never>)] = [:]

    private struct PendingPress {
        let appPID: pid_t?
        let actions: [RemoteTrigger: RemoteAction]
        var sequence: RemotePressSequence
        var timer: Task<Void, Never>?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        permissionOnboardingCompleted = defaults.bool(forKey: "device-setup-completed-v3")
        setupWelcomeCompleted = defaults.bool(forKey: "setup-welcome-completed-v1")
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
        var completed = configuration
        completed.completeSceneMappings()
        if completed != configuration { _ = updateConfiguration { $0 = completed } }
        syncVoice()
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
        refreshConnection()
        refreshPermissions()
    }

    func refreshPermissions() {
        guard permissionRefresh == nil else { return }
        permissionRefresh = Task { [weak self] in
            // Permission checks can block on tccd while System Settings applies a change.
            let snapshot = await Task.detached(priority: .userInitiated) {
                PermissionSnapshot(bluetooth: CBManager.authorization.rawValue,
                                   inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
                                   accessibility: AXIsProcessTrusted())
            }.value
            guard let self, !Task.isCancelled else { return }
            self.bluetoothAuthorization = CBManagerAuthorization(rawValue: snapshot.bluetooth) ?? .notDetermined
            self.canListen = snapshot.inputMonitoring
            self.canPost = snapshot.accessibility
            self.permissionStatusLoaded = true
            self.permissionRefresh = nil
            if self.canListen { self.hid.start() }
            else { self.hid.stop() }
        }
    }

    func isPermissionGranted(_ permission: RimoPermission) -> Bool {
        switch permission {
        case .bluetooth: bluetoothAuthorization == .allowedAlways
        case .inputMonitoring: canListen
        case .accessibility: canPost
        }
    }

    func requestPermission(_ permission: RimoPermission) {
        switch permission {
        case .bluetooth:
            if bluetoothAuthorization == .notDetermined { bluetoothRequest.start() }
            else { openPermissionSettings(permission) }
        case .inputMonitoring:
            requestInputAccess()
            openPermissionSettings(permission)
        case .accessibility:
            requestOutputAccess()
            openPermissionSettings(permission)
        }
    }

    func openPermissionSettings(_ permission: RimoPermission) {
        if let url = URL(string: permission.settingsURL) { NSWorkspace.shared.open(url) }
    }

    func beginSetup() {
        setupWelcomeCompleted = true
        defaults.set(true, forKey: "setup-welcome-completed-v1")
    }

    var setupPermission: RimoPermission? {
        guard let saved = defaults.string(forKey: "setup-permission-v1") else { return .accessibility }
        return RimoPermission(rawValue: saved)
    }

    func rememberSetupPermission(_ permission: RimoPermission?) {
        defaults.set(permission?.rawValue ?? "pairing", forKey: "setup-permission-v1")
    }

    func finishPermissionOnboarding() {
        permissionOnboardingCompleted = true
        defaults.set(true, forKey: "device-setup-completed-v3")
    }

    private func refreshConnection() {
        let addresses = HIDMonitor.connectedRemoteAddresses()
        isRemoteConnected = !addresses.isEmpty
        remoteAddress = addresses.count == 1 ? addresses.first : nil
        deviceInformation = remoteAddress.flatMap { HIDMonitor.deviceInformation(address: $0) }
        if addresses.count != 1 { batteryPercent = nil }
        else if let percent = HIDMonitor.batteryPercentage() { batteryPercent = percent }
        if addresses.count == 1 { voice.setAddress(addresses.first) }
    }

    func requestInputAccess() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    func requestOutputAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refresh()
    }

    func stop() {
        permissionRefresh?.cancel()
        permissionRefresh = nil
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
        guard sceneID == nil || sceneID.flatMap(scene) != nil else { return false }
        return updateConfiguration { $0.assign(action, to: button, trigger: trigger, sceneID: sceneID) }
    }

    func setActionEnabled(_ enabled: Bool, for button: RemoteButton, trigger: RemoteTrigger = .single, sceneID: String? = nil) {
        updateMappings(button, trigger: trigger, sceneID: sceneID) { $0.setEnabled(enabled, for: button, trigger: trigger) }
    }

    func followGlobal(_ button: RemoteButton, trigger: RemoteTrigger = .single, sceneID: String) {
        updateConfiguration {
            $0.restoreGlobal(button, trigger: trigger, sceneID: sceneID)
        }
    }

    func setAutomaticScenes(_ enabled: Bool) {
        updateConfiguration { $0.automatic = enabled }
    }

    @discardableResult
    func addScene(id: String, name: String) -> Bool {
        guard scene(id) == nil else { return false }
        return updateConfiguration {
            $0.scenes.append(AppSceneMapping(id: id, name: name, buttons: $0.global))
            $0.completeSceneMappings()
        }
    }

    func addScenes(_ applications: [(id: String, name: String, preset: ScenePreset?)]) -> Bool {
        guard !applications.isEmpty else { return false }
        return updateConfiguration { configuration in
            for selection in applications where !configuration.scenes.contains(where: { $0.id == selection.id }) {
                if let preset = selection.preset {
                    configuration.apply(preset, to: selection.id, name: selection.name)
                } else {
                    configuration.scenes.append(AppSceneMapping(id: selection.id, name: selection.name,
                                                               buttons: configuration.global))
                }
            }
            configuration.completeSceneMappings()
        }
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
        guard !configurationReadFailed else {
            toasts.show("无法保存映射", kind: .error, detail: configurationError)
            return false
        }
        var next = configuration
        edit(&next)
        do {
            defaults.set(try JSONEncoder().encode(next), forKey: storageKey)
            configuration = next
            // Cancel after updating configuration to ensure cancelled presses
            // see the new configuration state, not the old one.
            cancelPendingPresses()
            configurationError = nil
            syncVoice()
            return true
        } catch {
            configurationError = "未能保存映射。"
            toasts.show("映射保存失败", kind: .error, detail: configurationError)
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
                self?.toasts.show("快捷指令读取失败", kind: .error, detail: error.localizedDescription)
            }
        }
    }

    func runShortcut(_ shortcut: SystemShortcut) {
        guard runningShortcuts.insert(shortcut.id).inserted else { return }
        toasts.show("正在运行快捷指令", detail: shortcut.name)
        Task { [weak self] in
            defer { self?.runningShortcuts.remove(shortcut.id) }
            do {
                try await ShortcutsCLI.run(shortcut)
                self?.toasts.show("快捷指令已运行", kind: .success, detail: shortcut.name)
            } catch {
                self?.toasts.show("快捷指令运行失败", kind: .error, detail: error.localizedDescription)
            }
        }
    }

    func togglePaused() {
        paused.toggle()
        scrollMode.reset()
        cancelPendingPresses()
        syncVoice()
        toasts.show(paused ? "映射已暂停" : "映射已恢复")
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
            release(key, for: button)
        }
        if edge == .pressed {
            lastButton = button
            observedButtons.insert(button)
            // A new press ends any voice key still waiting for the audio tail.
            if let pending = pendingReleases.removeValue(forKey: button) {
                pending.task.cancel()
                _ = pending.key.post(pressed: false)
            }
        }

        let app = NSWorkspace.shared.frontmostApplication
        var press = pendingPresses.removeValue(forKey: button)
        press?.timer?.cancel()
        guard canDispatch() else {
            Self.log.info("\(button.rawValue, privacy: .public) ignored: paused=\(self.paused) recording=\(self.recording != nil)")
            return
        }
        if edge == .pressed, button == .siri {
            // Only route audio if the mapping that will actually execute requires voice input
            // Check only the triggers that could actually fire for this press
            let willRoute = siriWillStartVoiceInput(in: app?.bundleIdentifier)
            voice.siriPressed(routingAudio: willRoute)
        }
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
        guard var press = pendingPresses.removeValue(forKey: button), canDispatch(),
              press.appPID == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        if let trigger = press.sequence.advance(to: ProcessInfo.processInfo.systemUptime),
           let action = press.actions[trigger] {
            dispatch(action, heldBy: trigger == .hold ? button : nil)
            if action == .system(.toggleScrollMode) { return }
        }
        track(press, for: button)
    }

    private static let log = Logger(subsystem: "cn.yohoia.rimo", category: "mapping")

    private func canDispatch() -> Bool {
        !paused && recording == nil
    }

    /// A held voice key on Siri releases 0.3 s late so the last words reach
    /// the microphone before the input method stops listening.
    private func release(_ key: KeyboardShortcut, for button: RemoteButton) {
        guard button == .siri, RemoteAction.keyboard(key).startsVoiceInput else {
            _ = key.post(pressed: false)
            return
        }
        let task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            // Check isCancelled immediately after sleep to prevent double-release
            guard !Task.isCancelled, let self,
                  let pending = self.pendingReleases.removeValue(forKey: button),
                  !pending.task.isCancelled else { return }
            _ = pending.key.post(pressed: false)
        }
        pendingReleases[button] = (key, task)
    }

    /// Any trigger of the effective Siri mapping presses a voice key.
    private func siriStartsVoiceInput(in appID: String?) -> Bool {
        RemoteTrigger.allCases.contains { configuration.action(for: .siri, trigger: $0, in: appID)?.startsVoiceInput == true }
    }

    /// Check if audio routing is actually needed for Siri press.
    /// Only returns true if the single-tap or imminent action requires voice input.
    private func siriWillStartVoiceInput(in appID: String?) -> Bool {
        // Single tap is the most immediate trigger - check it first
        if let action = configuration.action(for: .siri, trigger: .single, in: appID),
           action.startsVoiceInput {
            return true
        }
        // Double-tap could fire if single-tap has no mapping
        if configuration.action(for: .siri, trigger: .single, in: appID) == nil,
           let action = configuration.action(for: .siri, trigger: .doublePress, in: appID),
           action.startsVoiceInput {
            return true
        }
        return false
    }

    /// The remote's audio capture runs only while some Siri mapping (global or
    /// an enabled scene) presses a voice key.
    private func syncVoice() {
        let mappings = [configuration.global] + configuration.scenes.filter(\.enabled).map { $0.resolved(global: configuration.global) }
        voice.setWanted(!paused && mappings.contains { buttons in
            RemoteTrigger.allCases.contains { buttons.isEnabled(.siri, trigger: $0) && buttons[.siri, $0]?.startsVoiceInput == true }
        })
    }

    private func cancelPendingPresses() {
        for press in pendingPresses.values { press.timer?.cancel() }
        pendingPresses.removeAll()
        for key in heldOutputs.values { _ = key.post(pressed: false) }
        heldOutputs.removeAll()
        for pending in pendingReleases.values { pending.task.cancel(); _ = pending.key.post(pressed: false) }
        pendingReleases.removeAll()
    }

    private func dispatch(_ action: RemoteAction, heldBy button: RemoteButton? = nil) {
        Self.log.info("dispatch \(action.title, privacy: .public)")
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
            else {
                actionError = "无法发送按键，请检查辅助功能权限。"
                toasts.show("请开启辅助功能权限", kind: .error)
                canPost = CGPreflightPostEventAccess()
            }
            return
        }
        do { try ActionOutput.perform(action) }
        catch {
            Self.log.error("action failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription; canPost = CGPreflightPostEventAccess()
            toasts.show("动作执行失败", kind: .error, detail: error.localizedDescription)
        }
    }
}

private struct PermissionSnapshot: Sendable {
    let bluetooth: Int
    let inputMonitoring: Bool
    let accessibility: Bool
}

@MainActor
private final class BluetoothPermissionRequest: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private let changed: () -> Void

    init(changed: @escaping () -> Void) {
        self.changed = changed
        super.init()
    }

    func start() {
        manager = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in self?.changed() }
    }
}

enum RimoPermission: String, CaseIterable, Identifiable {
    case accessibility, inputMonitoring, bluetooth

    var id: Self { self }
    var title: String {
        switch self {
        case .bluetooth: "蓝牙"
        case .inputMonitoring: "输入监控"
        case .accessibility: "辅助功能"
        }
    }
    var symbol: String {
        switch self {
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .inputMonitoring: "keyboard"
        case .accessibility: "accessibility"
        }
    }
    var purpose: String {
        switch self {
        case .bluetooth: "允许 Rimo 访问蓝牙设备。"
        case .inputMonitoring: "允许 Rimo 读取遥控器按键。"
        case .accessibility: "允许 Rimo 向当前应用程序发送按键和快捷键。"
        }
    }
    var instructions: String {
        "在系统设置的“隐私与安全性”中打开“\(title)”，找到 Rimo 并开启权限。"
    }
    var settingsURL: String {
        let pane: String
        switch self {
        case .bluetooth: pane = "Privacy_Bluetooth"
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        case .accessibility: pane = "Privacy_Accessibility"
        }
        return "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    }
}
