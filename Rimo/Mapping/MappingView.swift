import AppKit
import Carbon.HIToolbox
import SwiftUI

struct MappingView: View {
    @ObservedObject var model: RimoModel
    @Binding var selected: RemoteButton?
    var sceneID: String? = nil
    var appPickerVisible = false
    let presentationActive: Bool
    var onReady: () -> Void = {}

    @State private var recentlyPressed: RemoteButton?
    @State private var pressCount = 0
    @State private var pose = RemotePose.detail
    @State private var dragging = false
    @State private var idleSince = Date.now
    @State private var camera = RemoteCameraMotion()
    @State private var frameTime = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    private var wantsFocusedCamera: Bool { selected != nil || appPickerVisible }

    private var frameInterval: TimeInterval {
        if presentationActive && camera.movement != nil { return 1.0 / 60 }
        return isSwaying ? 1.0 / 30 : 3600
    }

    private var isSwaying: Bool {
        presentationActive && model.isRemoteConnected && selected == nil && !appPickerVisible && camera.movement == nil
            && !reduceMotion && activeState != .inactive && !dragging && pose == .detail
    }

    var body: some View {
        GeometryReader { geometry in
            let progress = camera.progress(at: frameTime)
            let presentation = ButtonStage(size: geometry.size, progress: progress)
            render(presentation, pose: displayedPose(at: frameTime), breathing: glow(at: frameTime))
            .onReceive(model.$lastButton.dropFirst()) { button in
                guard model.isRemoteConnected, let button, RemoteButton.a2540Buttons.contains(button) else { return }
                let projection = ButtonStage(size: geometry.size, progress: 0).projection
                if model.isSettingsFocused(), selected == nil, !dragging,
                   RemoteModelView.focusBounds(for: button, in: projection, pose: pose) == nil {
                    orbit(.reset)
                }
                recentlyPressed = button
                pressCount &+= 1
            }
        }
        .task(id: frameInterval) {
            frameTime = .now
            guard frameInterval < 1 else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(frameInterval)) }
                catch { return }
                frameTime = .now
            }
        }
        .onAppear { camera.reset(focused: wantsFocusedCamera); frameTime = .now }
        .onChange(of: wantsFocusedCamera) { focused in changeFocus(focused: focused) }
        .onChange(of: presentationActive) { active in
            if active {
                idleSince = .now
                camera.reset(focused: wantsFocusedCamera)
                pose = .detail
            }
        }
        .onChange(of: activeState) { if $0 != .inactive { idleSince = .now } }
        .onChange(of: reduceMotion) { enabled in if enabled { camera.reset(focused: wantsFocusedCamera) } }
        .onChange(of: model.isRemoteConnected) { connected in
            if connected {
                idleSince = .now
            } else {
                camera.reset(focused: false)
                selected = nil
                recentlyPressed = nil
                dragging = false
                pose = .detail
            }
        }
        .task(id: camera.movement?.startedAt) {
            guard let movement = camera.movement else { return }
            try? await Task.sleep(for: .seconds(movement.duration))
            if !Task.isCancelled { camera.finish(startedAt: movement.startedAt) }
        }
        .task(id: pressCount) {
            try? await Task.sleep(for: .milliseconds(520))
            if !Task.isCancelled { recentlyPressed = nil }
        }
        .transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
    }

    private func render(_ stage: ButtonStage, pose: RemotePose, breathing: Double) -> some View {
        let projection = stage.projection
        let button = appPickerVisible ? nil : selected
        let mappings = model.mappings(sceneID: sceneID)
        let mappedButtons = Set(RemoteButton.a2540Buttons.filter { button in
            RemoteTrigger.allCases.contains { trigger in
                mappings.isEnabled(button, trigger: trigger) && mappings[button, trigger]?.isAssignable(to: button) == true
            }
        })
        return ZStack(alignment: .topLeading) {
            if presentationActive && model.isRemoteConnected {
                RemoteAmbientGlow(breathing: breathing)
                    .frame(width: min(stage.size.width * 0.66, 580), height: min(stage.size.height, 535))
                    .position(x: stage.remoteX, y: stage.glowY)
                    .opacity(1 - 0.32 * stage.progress)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            RemoteModelView(selected: button, recentlyPressed: recentlyPressed, pose: pose,
                            projection: projection, outlineOpacity: stage.outlineOpacity,
                            mappedButtons: mappedButtons,
                            canOrbit: selected == nil && !appPickerVisible && camera.movement == nil,
                            onOrbit: orbit, onSelect: select, onReady: onReady)
                .frame(width: projection.size.width, height: projection.size.height)
                .saturation(model.isRemoteConnected ? 1 : 0)
                .contrast(model.isRemoteConnected ? 1 : 0.65)
                .opacity(model.isRemoteConnected ? 1 : 0.45)
                .disabled(!model.isRemoteConnected)
                .allowsHitTesting(model.isRemoteConnected)
                .accessibilityValue(model.isRemoteConnected ? "已连接" : "未连接，遥控器已禁用")
                .overlay {
                    if presentationActive && stage.nameOpacity > 0 {
                        Text(A2540Input.modelName)
                            .font(RimoStyle.modelHeading)
                            .tracking(1)
                            .foregroundStyle(model.isRemoteConnected ? RimoStyle.ink : RimoStyle.muted)
                            .position(x: projection.size.width / 2,
                                      y: RemoteModelView.bodyBounds(in: projection, pose: pose).maxY + 22)
                            .opacity(stage.nameOpacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(stage.nameOpacity < 0.75)
                    }
                }
                .clipped()
                .position(x: stage.remoteX, y: stage.size.height / 2)

        }
        .frame(width: stage.size.width, height: stage.size.height)
        .clipped()
    }

    private func changeFocus(focused: Bool) {
        let now = Date.now
        let currentPose = displayedPose(at: now)
        let currentGlow = glow(at: now)
        dragging = false
        pose = .detail
        camera.retarget(focused: focused, at: now, pose: currentPose, glow: currentGlow,
                        reduceMotion: reduceMotion)
        frameTime = now
        if !focused { idleSince = now.addingTimeInterval(camera.movement?.duration ?? 0) }
    }

    private func displayedPose(at time: Date) -> RemotePose {
        if let movement = camera.movement {
            return movement.fromPose.blended(to: .detail, fraction: movement.eased(at: time))
        }
        return isSwaying ? pose.swaying(elapsed: time.timeIntervalSince(idleSince)) : pose
    }

    private func glow(at time: Date) -> Double {
        if let movement = camera.movement {
            return movement.fromGlow + (0.45 - movement.fromGlow) * movement.eased(at: time)
        }
        guard isSwaying else { return 0.45 }
        let elapsed = max(0, time.timeIntervalSince(idleSince))
        return 0.45 + min(1, elapsed) * 0.46 * sin(elapsed * 2 * .pi / 6.4)
    }

    private func orbit(_ change: RemoteOrbitChange) {
        guard model.isRemoteConnected, selected == nil, camera.movement == nil else { return }
        switch change {
        case .dragging(let next): dragging = true; pose = next
        case .inspecting(let next): dragging = false; pose = next
        case .reset: dragging = false; pose = .detail; idleSince = .now
        }
    }

    private func select(_ button: RemoteButton) {
        guard model.isRemoteConnected else { return }
        selected = button
    }
}

struct RemoteCameraMotion {
    private(set) var focused = false
    private(set) var movement: CameraMovement?

    func progress(at time: Date) -> Double {
        movement?.progress(at: time) ?? (focused ? 1 : 0)
    }

    mutating func reset(focused: Bool) {
        self.focused = focused
        movement = nil
    }

    mutating func retarget(focused: Bool, at time: Date, pose: RemotePose, glow: Double, reduceMotion: Bool) {
        guard focused != self.focused else { return }
        let current = progress(at: time)
        self.focused = focused
        movement = reduceMotion ? nil : CameraMovement(startedAt: time, from: current, to: focused ? 1 : 0,
                                                       fromPose: pose, fromGlow: glow)
    }

    mutating func finish(startedAt: Date) {
        guard movement?.startedAt == startedAt else { return }
        movement = nil
    }
}

struct CameraMovement {
    let startedAt: Date
    let from: Double
    let to: Double
    let fromPose: RemotePose
    let fromGlow: Double

    var duration: TimeInterval { (to == 1 ? 0.52 : 0.34) * max(0.38, abs(to - from)) }

    func eased(at time: Date) -> Double {
        let t = min(1, max(0, time.timeIntervalSince(startedAt) / duration))
        return t * t * (3 - 2 * t)
    }

    func progress(at time: Date) -> Double {
        from + (to - from) * eased(at: time)
    }
}

enum ActionSidebarLayout {
    static func width(in availableWidth: CGFloat) -> CGFloat { availableWidth / 3 }
}

private struct ButtonStage {
    let size: CGSize
    let progress: Double

    var stageWidth: CGFloat { size.width - ActionSidebarLayout.width(in: size.width) }
    var remoteX: CGFloat { interpolate(size.width / 2, stageWidth * 0.55) }
    var projection: RemoteProjection {
        let viewportWidth = max(1, min(535, stageWidth - 25))
        let restingUnit = max(0.1, RemotePresentation.height(in: size.height) / 14)
        // Frame z=-6.76 (top of shell) through z=1.93 (lowest key).
        // The lateral limit reserves space for both label columns beside the model.
        let focusedUnit = max(restingUnit, min((size.height - 90) / 8.69,
                                              (viewportWidth - RemoteModelView.focusedHorizontalInset - 12) / 3.9))
        let restingOrigin = RemotePresentation.centerY(in: size.height)
        let focusedOrigin = 32 + 6.76 * focusedUnit
        return RemoteProjection(size: CGSize(width: viewportWidth, height: size.height),
                                unit: interpolate(restingUnit, focusedUnit),
                                originY: interpolate(restingOrigin, focusedOrigin))
    }
    var glowY: CGFloat { projection.y(at: -3.2 * progress) }
    var nameOpacity: Double { 1 - min(1, progress / 0.32) }
    var outlineOpacity: Double { reveal(from: 0.56, to: 0.91) }

    private func interpolate(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * progress }
    private func reveal(from: Double, to: Double) -> Double {
        let t = min(1, max(0, (progress - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }
}

private struct RemoteAmbientGlow: View {
    let breathing: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let green = Color(red: 100.0 / 255, green: 193.0 / 255, blue: 139.0 / 255)
            let strength = (colorScheme == .dark ? 0.20 : 0.16) * (0.60 + 0.40 * breathing)
            RadialGradient(colors: [green.opacity(strength), green.opacity(strength * 0.48), green.opacity(0)],
                           center: .center, startRadius: 0,
                           endRadius: min(geometry.size.width * 0.47, geometry.size.height * 0.46) * (0.93 + 0.13 * breathing))
        }
    }
}

struct RimoKeycap: View {
    let title: String

    var body: some View {
        Text(title)
            .font(RimoStyle.label)
            .foregroundStyle(RimoStyle.ink)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RimoStyle.surface, in: RimoStyle.controlShape)
            .overlay {
                RimoStyle.controlShape
                    .strokeBorder(RimoStyle.line)
                    .allowsHitTesting(false)
            }
    }
}

struct ButtonMappingEditor: View {
    @ObservedObject var model: RimoModel
    let button: RemoteButton
    var sceneID: String? = nil
    var inSidebar = false
    let close: () -> Void
    @State private var trigger = RemoteTrigger.single
    @State private var recordingState = RecordingState.idle
    @State private var recordingFeedback: Bool?
    @State private var draftFlags: NSEvent.ModifierFlags = []
    @State private var kindOverride: EditorKind?
    @State private var draftText = ""
    @State private var draftReturn = false
    @State private var expandedAction: ActionRowID?
    @State private var actionQuery = ""
    @State private var openGroups: Set<ActionGroup> = []
    @State private var showingActionSetup = false
    @State private var rowTriggers: [ActionRowID: RemoteTrigger] = [:]
    @State private var recommendedOrder: [ActionChoice] = []
    @FocusState private var searchingActions: Bool

    private var mappings: ButtonMappings { model.mappings(sceneID: sceneID) }
    private var action: RemoteAction? { mappings[button, trigger] }
    private var capturing: Bool {
        if case .listening = recordingState { return true }
        return false
    }
    private var editingRecording: Bool { recordingState != .idle }
    private var keyboard: KeyboardShortcut? {
        if case .keyboard(let key) = action { return key }
        return nil
    }
    private var currentShortcut: SystemShortcut? {
        if case .shortcut(let shortcut) = action { return shortcut }
        return nil
    }
    /// The Siri key is the remote's microphone key: mapping it to an input
    /// method's voice key (Fn, Option…) also sends the remote's audio.
    private var voiceKey: Bool { button == .siri }

    private var scene: AppSceneMapping? { sceneID.flatMap(model.scene) }

    var body: some View {
        Group {
            if inSidebar { sidebar } else { sceneEditor }
        }
        .font(RimoStyle.body)
        .onAppear(perform: loadTextDraft)
        .onAppear(perform: revealCurrentConfiguration)
        .onAppear { recommendedOrder = groupChoices(.recommended) }
        .onChange(of: trigger) { _ in loadTextDraft() }
        .onChange(of: action) { next in
            if kind.wrappedValue != .text { loadTextDraft() }
            if let next, let row = expandedAction, row.group == .recommended {
                let replacement = ActionChoice(current: next)
                recommendedOrder = recommendedOrder.map { $0 == row.choice ? replacement : $0 }
                expandedAction = ActionRowID(group: .recommended, choice: replacement)
            }
        }
        .onDisappear(perform: stopCapture)
        .sheet(isPresented: $showingActionSetup, onDismiss: closeActionConfiguration) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(kind.wrappedValue.title).font(RimoStyle.title)
                    Spacer()
                    Button("完成") { showingActionSetup = false }
                        .keyboardShortcut(.defaultAction)
                }
                Text("\(button.title) · \(trigger.title)")
                    .font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
                ScrollView { configurationFields }
            }
            .padding(24)
            .frame(width: 380, height: 480)
            .rimoToastHost(model.toasts)
        }
        .background {
            if capturing {
                ShortcutCapture { shortcut in
                    recordingState = .review(shortcut)
                } onModifiers: { flags in
                    recordingState = .listening(flags)
                } onCancel: {
                    stopCapture()
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("动作")
                    .font(.system(size: 20, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 32)
            .frame(height: 70)
            .background(RimoStyle.actionSidebarHeader)

            actionBrowser
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RimoStyle.surface)
    }

    private var sceneEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorHeader
            RimoDivider()
            triggerPicker
            if voiceKey, action?.startsVoiceInput == true {
                VoiceKeyStatus(voice: model.voice, helper: model.voice.helper)
            }
            configurationFields
            sceneActionStatus
        }
        .padding(RimoStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RimoStyle.surface, in: RimoStyle.controlShape)
        .modifier(RimoCardRings())
    }

    private var editorHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: button.glyph)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(RimoStyle.actionLabel)
                .frame(width: 40, height: 40)
                .background(RimoStyle.action, in: RimoStyle.controlShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(button.title).font(.system(size: 19, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(actionSummary)
                    .font(RimoStyle.label)
                    .foregroundStyle(RimoStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭按键编辑")
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder private var sceneActionStatus: some View {
        if scene?.inherits(button, trigger: trigger) == true {
            hint("跟随全局映射。修改后只影响这个场景。")
        } else if scene?.canFollowGlobal == true, let sceneID {
            Button("恢复跟随全局") {
                kindOverride = nil
                draftFlags = []
                recordingFeedback = nil
                model.followGlobal(button, trigger: trigger, sceneID: sceneID)
            }
            .buttonStyle(.borderless)
            .disabled(editingRecording)
        }
    }

    private var actionBrowser: some View {
        let query = actionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !query.isEmpty
        let groups = ActionGroup.allCases.filter { group in
            !searching || (group != .recommended && (group.title.localizedStandardContains(query)
                || groupChoices(group).contains { $0.matches(query) }))
        }
        return VStack(alignment: .leading, spacing: 0) {
            if trigger != .single, let single = mappings[button], mappings.isEnabled(button), single.holdsUntilRelease {
                Text("单击当前是「\(single.title) · 按住至松开」，按下时立即开始并保持到松开，所以不会再识别双击和长按。要使用它们，请把单击改成“触发一次”。")
                    .font(RimoStyle.label)
                    .foregroundStyle(RimoStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)
            }
            actionSearchField
            sidebarDivider
            ScrollView {
                actionGroups(groups, query: query, searching: searching)
            }

        }
        .onChange(of: actionQuery) { _ in closeActionConfiguration() }
        .onChange(of: searchingActions) { if $0 { stopCapture() } }
    }

    @ViewBuilder private func actionGroups(_ groups: [ActionGroup], query: String, searching: Bool) -> some View {
        if groups.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("没有符合的动作").font(RimoStyle.title)
                hint("试试「快捷键」「滚动」或「播放」。")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(34)
        } else {
            VStack(spacing: 0) {
                ForEach(groups) { group in
                    if searching || group == .recommended {
                        Text(group.title)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 50)
                            .padding(.horizontal, 33)
                            .accessibilityAddTraits(.isHeader)
                    } else {
                        actionGroupButton(group)
                    }
                    if searching || group == .recommended || openGroups.contains(group) {
                        let items = groupChoices(group).filter {
                            !searching || group.title.localizedStandardContains(query) || $0.matches(query)
                        }
                        VStack(spacing: 0) {
                            if group == .keyboard && !searching {
                                actionRow(.configure(.keyboard), in: group)
                                ForEach(SystemAction.editingActions) { actionRow(.system($0), in: group) }
                                ForEach(KeyboardShortcut.keyGroups) { section in
                                    Text(section.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(RimoStyle.muted)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 18)
                                        .padding(.bottom, 8)
                                        .accessibilityAddTraits(.isHeader)
                                    ForEach(section.keys) { actionRow(.key($0.id), in: group) }
                                }
                            } else {
                                ForEach(items) { actionRow($0, in: group) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    if group != groups.last { sidebarDivider }
                }
            }
        }
    }

    private var sidebarDivider: some View {
        Rectangle().fill(RimoStyle.actionSidebarDivider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var actionSearchField: some View {
        HStack(spacing: 12) {
            TextField("搜索", text: $actionQuery, prompt: Text("搜索").foregroundColor(RimoStyle.actionSearchPlaceholder))
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .foregroundStyle(searchingActions ? RimoStyle.action : RimoStyle.ink)
                .focused($searchingActions)
                .accessibilityLabel("搜索动作")
            if !actionQuery.isEmpty {
                Button {
                    actionQuery = ""
                    searchingActions = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(RimoStyle.action)
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            } else {
                Button {
                    searchingActions = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(RimoStyle.ink)
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("聚焦动作搜索")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 48)
        .background(RimoStyle.surface, in: RimoStyle.controlShape)
        .overlay {
            RimoStyle.controlShape
                .strokeBorder(searchingActions ? RimoStyle.action : RimoStyle.line)
                .allowsHitTesting(false)
        }
        .padding(16)
    }

    private func actionGroupButton(_ group: ActionGroup) -> some View {
        let expanded = openGroups.contains(group)
        return Button {
            if expanded {
                if expandedAction?.group == group { closeActionConfiguration() }
                openGroups.remove(group)
            } else {
                openGroups.insert(group)
            }
        } label: {
            HStack {
                Text(group.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(expanded ? RimoStyle.assignmentAccent : RimoStyle.ink)
            .padding(.horizontal, 33)
            .frame(height: 50)
        }
        .buttonStyle(ActionBrowserRowStyle())
        .accessibilityValue(expanded ? "已展开" : "已折叠")
    }

    private func actionRow(_ choice: ActionChoice, in group: ActionGroup) -> some View {
        let row = ActionRowID(group: group, choice: choice)
        let expanded = expandedAction == row
        let restriction = assignmentRestriction(for: choice.action)
        let assigned = RemoteTrigger.allCases.first { mode in
            mappings[button, mode].map(choice.represents) == true
        }
        let mode = assigned ?? rowTriggers[row] ?? .single
        let enabled = assigned.map { mappings.isEnabled(button, trigger: $0) } ?? false
        let highlighted = expanded || (assigned != nil && (group == .recommended || !actionQuery.isEmpty))
        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                Button {
                    selectAction(choice, in: group, trigger: mode, configure: true)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.title)
                                .font(.system(size: 14, weight: highlighted ? .medium : .regular))
                                .lineLimit(2)
                            if let restriction {
                                Text(restriction).font(RimoStyle.label)
                            } else if assigned != nil && !enabled {
                                Text("已停用").font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(restriction != nil ? RimoStyle.muted : RimoStyle.ink)
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityValue(assigned.map { "\($0.title)，\(enabled ? "已绑定" : "已停用")" } ?? "未绑定")

                ActionTriggerPicker(selection: mode, assigned: assigned != nil && enabled,
                                    actionTitle: choice.title,
                                    unavailable: unavailableTriggers) { selected in
                    selectAction(choice, in: group, trigger: selected)
                }
                .frame(width: 100, alignment: .trailing)
                .padding(.trailing, 10)
            }
            .background(highlighted ? RimoStyle.assignmentAccent.opacity(0.08) : .clear,
                        in: RimoStyle.controlShape)
            .contentShape(Rectangle())
            .disabled(restriction != nil || editingRecording)

        }
        .padding(.bottom, highlighted ? 6 : 0)
        .id(row)
    }

    private var unavailableTriggers: Set<RemoteTrigger> {
        if let single = mappings[button], mappings.isEnabled(button), single.holdsUntilRelease {
            return [.doublePress, .hold]
        }
        return []
    }

    private func selectAction(_ choice: ActionChoice, in group: ActionGroup, trigger selected: RemoteTrigger,
                              configure: Bool = false) {
        guard !unavailableTriggers.contains(selected) else { return }
        let row = ActionRowID(group: group, choice: choice)
        let previous = choice.action.flatMap { candidate in
            RemoteButton.allCases.lazy.flatMap { other in
                RemoteTrigger.allCases.map { (other, $0) }
            }.first { other, mode in
                (other != button || mode != selected) && mappings[other, mode]?.matchesBinding(candidate) == true
            }
        }
        stopCapture()
        searchingActions = false
        closeActionConfiguration()
        trigger = selected
        rowTriggers[row] = selected
        if let immediate = choice.action {
            guard model.setAction(immediate, for: button, trigger: selected, sceneID: sceneID) else { return }
        }
        kind.wrappedValue = choice.kind
        draftFlags = []
        loadTextDraft()
        expandedAction = row
        if case .configure = choice { showingActionSetup = true }
        else if configure, case .saved = choice { showingActionSetup = true }
        if let previous {
            model.toasts.show("已改为\(selected.title)", kind: .success,
                              detail: "「\(choice.title)」：\(previous.0.title) · \(previous.1.title) → \(button.title) · \(selected.title)")
        }
    }

    private func assignmentRestriction(for action: RemoteAction?) -> String? {
        action?.isAssignable(to: button) == false ? "仅可分配给非方向键" : nil
    }

    private func groupChoices(_ group: ActionGroup) -> [ActionChoice] {
        switch group {
        case .recommended:
            let suggested: [ActionChoice] = switch button {
            case .playPause: [.media(.playPause), .key(UInt16(kVK_Space)), .media(.nextTrack)]
            case .volumeUp: [.media(.volumeUp), .system(.toggleScrollMode)]
            case .volumeDown: [.media(.volumeDown), .system(.toggleScrollMode)]
            case .mute: [.media(.mute), .media(.playPause)]
            case .home: [.system(.missionControl), .system(.showDesktop), .configure(.openApp)]
            case .select: [.key(UInt16(kVK_Return)), .key(UInt16(kVK_Space))]
            case .up: [.key(UInt16(kVK_UpArrow)), .key(UInt16(kVK_PageUp))]
            case .down: [.key(UInt16(kVK_DownArrow)), .key(UInt16(kVK_PageDown))]
            case .left: [.key(UInt16(kVK_LeftArrow)), .system(.previousDesktop), .media(.previousTrack)]
            case .right: [.key(UInt16(kVK_RightArrow)), .system(.nextDesktop), .media(.nextTrack)]
            case .back, .menu: [.key(UInt16(kVK_Escape)), .system(.showDesktop)]
            case .power: [.system(.sleepDisplay), .system(.lockScreen)]
            // Siri: open Siri, or press an input method's voice key (Voxa's
            // Typeless = Fn, Doubao/WeChat = Option), which also sends the audio.
            case .siri: [.system(.activateSiri), .key(UInt16(kVK_Function)), .key(UInt16(kVK_RightOption)),
                         .key(UInt16(kVK_Option)), .configure(.keyboard)]
            }
            var result = suggested
            if !result.contains(.configure(.keyboard)) { result.append(.configure(.keyboard)) }
            let assigned = RemoteTrigger.allCases.compactMap { mappings[button, $0] }.map(ActionChoice.init(current:))
            for current in assigned.reversed() {
                result.removeAll { $0 == current }
                result.insert(current, at: 0)
            }
            if let expandedAction, expandedAction.group == .recommended, !result.contains(expandedAction.choice) {
                result.insert(expandedAction.choice, at: 0)
            }
            if !recommendedOrder.isEmpty {
                result = recommendedOrder.filter { result.contains($0) }
                    + result.filter { !recommendedOrder.contains($0) }
            }
            return result
        case .keyboard:
            return [.configure(.keyboard)] + SystemAction.editingActions.map(ActionChoice.system)
                + ActionChoice.presetKeyCodes.map(ActionChoice.key)
        case .media: return MediaAction.allCases.map(ActionChoice.media)
        case .windows:
            return SystemAction.windowActions.map(ActionChoice.system)
        case .system: return SystemAction.systemActions.map(ActionChoice.system)
        case .other: return SystemAction.otherActions.map(ActionChoice.system)
        case .apps: return [.configure(.openApp), .configure(.shortcut)]
        }
    }

    private func closeActionConfiguration() {
        stopCapture()
        kindOverride = nil
        draftFlags = []
        recordingFeedback = nil
        expandedAction = nil
    }

    private func revealCurrentConfiguration() {
        guard inSidebar, let action else { return }
        let choice = ActionChoice(current: action)
        if case .saved = choice {
            expandedAction = ActionRowID(group: .recommended, choice: choice)
        }
    }

    private func changeTrigger(to item: RemoteTrigger) {
        guard trigger != item else { return }
        trigger = item
        actionQuery = ""
        closeActionConfiguration()
        revealCurrentConfiguration()
    }

    private var triggerPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("触发方式").font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
            HStack(spacing: 6) {
                ForEach(RemoteTrigger.allCases) { item in
                    Button {
                        changeTrigger(to: item)
                    } label: {
                        Text(item.title).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RimoButtonStyle(primary: trigger == item))
                    .accessibilityAddTraits(trigger == item ? .isSelected : [])
                }
            }
            if trigger != .single {
                Text(trigger == .doublePress ? "在遥控器上快速按同一个键两次。" : "在遥控器上按住约半秒。")
                    .font(RimoStyle.label)
                    .foregroundStyle(RimoStyle.muted)
            }
        }
    }

    private var configurationFields: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !inSidebar {
                HStack(spacing: 4) {
                    Text("按键动作")
                        .font(RimoStyle.label)
                        .foregroundStyle(RimoStyle.muted)
                    Spacer()
                    Picker("按键动作", selection: kind) {
                        ForEach(EditorKind.allCases.filter { ![.mouse, .scroll, .text].contains($0) || kind.wrappedValue == $0 }) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .controlSize(.regular)
                    .frame(maxWidth: 180)
                    .disabled(editingRecording)
                }
            }

            if kind.wrappedValue == .keyboard {
                recordField
                HStack(spacing: 7) {
                    modifier("command", "Command", .command)
                    modifier("option", "Option", .option)
                    modifier("control", "Control", .control)
                    modifier("shift", "Shift", .shift)
                    modifier("fn", "Fn", .function)
                }
                Picker("按键", selection: keySelection) {
                    Text("选择按键").tag(nil as UInt16?)
                    if let keyboard, !KeyboardShortcut.navigationKeys.contains(where: { $0.id == keyboard.keyCode }) {
                        Text(keyboard.label).tag(Optional(keyboard.keyCode))
                    }
                    ForEach(KeyboardShortcut.navigationKeys) { key in
                        Text(key.title).tag(Optional(key.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(editingRecording)
                keyboardBehavior
            } else {
                additionalFields
            }

            if let error = model.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(RimoStyle.label)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action, !inSidebar || EditorKind(action: action) == kind.wrappedValue {
                if inSidebar { RimoDivider() }
                HStack(spacing: 8) {
                    Text("启用此触发").font(RimoStyle.label)
                    Toggle("启用此触发", isOn: Binding(get: { mappings.isEnabled(button, trigger: trigger) }, set: {
                        model.setActionEnabled($0, for: button, trigger: trigger, sceneID: sceneID)
                    }))
                    .labelsHidden()
                    .toggleStyle(RimoPillSwitch())
                    .disabled(editingRecording)
                    Spacer(minLength: 0)
                    Button("清除") {
                        recordingFeedback = nil
                        model.setAction(nil, for: button, trigger: trigger, sceneID: sceneID)
                        loadTextDraft()
                    }
                        .buttonStyle(.borderless)
                        .disabled(editingRecording)
                }
                .padding(.top, 4)
            } else if !inSidebar {
                hint("设置动作后可启用此触发。")
            }
        }
    }

    private var recordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                switch recordingState {
                case .idle:
                    if let keyboard {
                        RimoKeycap(title: recordingTitle(for: keyboard))
                    } else {
                        Text("未录制").foregroundStyle(RimoStyle.muted)
                    }
                    Spacer(minLength: 6)
                    Button("开始录制") {
                        recordingFeedback = nil
                        model.startRecording(button)
                        recordingState = .listening([])
                    }
                    .buttonStyle(RimoButtonStyle(primary: true))
                    .accessibilityHint("按住修饰键后再按下其他键，可录制组合快捷键。")
                case .listening(let flags):
                    let symbols = recordingSymbols(flags)
                    if symbols.isEmpty {
                        Text("请按下快捷键").foregroundStyle(RimoStyle.muted)
                    } else {
                        RimoKeycap(title: symbols.joined(separator: " "))
                    }
                    Spacer(minLength: 6)
                    Button("取消", action: stopCapture).buttonStyle(RimoButtonStyle())
                case .review(let shortcut):
                    RimoKeycap(title: recordingTitle(for: shortcut))
                        .accessibilityLabel("已录制：\(recordingTitle(for: shortcut))")
                    Spacer(minLength: 6)
                    Button("取消", action: stopCapture).buttonStyle(RimoButtonStyle())
                    Button("保存") {
                        let saved = model.setAction(.keyboard(shortcut), for: button, trigger: trigger, sceneID: sceneID)
                        if saved { stopCapture() }
                        recordingFeedback = saved
                    }
                    .buttonStyle(RimoButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: inSidebar ? 48 : 44)
            .foregroundStyle(RimoStyle.ink)
            .background(inSidebar ? RimoStyle.surface : RimoStyle.canvas, in: RimoStyle.controlShape)
            .overlay {
                RimoStyle.controlShape.strokeBorder(
                    editingRecording ? RimoStyle.ink : RimoStyle.line,
                    lineWidth: capturing ? 1.5 : 1
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            if let recordingFeedback {
                Label(recordingFeedback ? "快捷键已保存" : "未能保存快捷键，请重试。",
                      systemImage: recordingFeedback ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(RimoStyle.label)
                    .foregroundStyle(recordingFeedback ? RimoStyle.success : RimoStyle.ink)
            } else if capturing {
                Text("按 Esc 取消录制。").font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
            }
        }
    }

    private func recordingSymbols(_ flags: NSEvent.ModifierFlags) -> [String] {
        let pairs: [(NSEvent.ModifierFlags, String)] = [(.command, "⌘"), (.shift, "⇧"), (.option, "⌥"), (.control, "⌃"), (.function, "Fn")]
        return pairs.compactMap { flags.contains($0.0) ? $0.1 : nil }
    }

    private func recordingTitle(for key: KeyboardShortcut) -> String {
        key.title
    }

    @ViewBuilder private var shortcutPicker: some View {
        let available = model.systemShortcuts
        VStack(alignment: .leading, spacing: 6) {
            if model.loadingShortcuts {
                ProgressView().controlSize(.small)
            } else if let error = model.shortcutListError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(RimoStyle.ink).fixedSize(horizontal: false, vertical: true)
                Button("重新读取") { model.loadShortcuts(force: true) }
            } else if available.isEmpty {
                Text("没有可用的快捷指令").foregroundStyle(RimoStyle.muted)
                Button("打开 macOS 快捷指令") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                }
                    .buttonStyle(.link)
                    .foregroundStyle(RimoStyle.ink)
            } else {
                Picker("选择快捷指令", selection: Binding(get: { currentShortcut?.id }, set: { id in
                    if let item = available.first(where: { $0.id == id }) {
                        model.setAction(.shortcut(item), for: button, trigger: trigger, sceneID: sceneID)
                    } else if currentShortcut != nil {
                        model.setAction(nil, for: button, trigger: trigger, sceneID: sceneID)
                    }
                })) {
                    Text("选择快捷指令").tag(nil as UUID?)
                    if let currentShortcut, !available.contains(where: { $0.id == currentShortcut.id }) {
                        Text("找不到：\(currentShortcut.name)").tag(Optional(currentShortcut.id))
                    }
                    ForEach(available) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
            }
        }
        .task { model.loadShortcuts() }
    }

    private var actionSummary: String {
        guard let action else { return "未设置映射" }
        if case .keyboard(let key) = action {
            return key.title + (key.holdsUntilRelease == true ? " · 按住至松开" : "")
        }
        return action.title
    }

    private var kind: Binding<EditorKind> {
        Binding(get: { kindOverride ?? EditorKind(action: action) }, set: { next in
            stopCapture()
            recordingFeedback = nil
            kindOverride = next
            if next == .text { loadTextDraft() }
        })
    }

    private func save(_ action: RemoteAction) {
        recordingFeedback = nil
        _ = model.setAction(action, for: button, trigger: trigger, sceneID: sceneID)
    }

    @ViewBuilder private var additionalFields: some View {
        switch kind.wrappedValue {
        case .keyboard: EmptyView()
        case .shortcut: shortcutPicker
        case .mouse:
            Picker("鼠标动作", selection: Binding(get: {
                if case .mouse(let value) = action { return Optional(value) }; return nil
            }, set: { if let value = $0 { save(.mouse(value)) } })) {
                Text("选择鼠标动作").tag(nil as MouseAction?)
                ForEach(MouseAction.allCases) { Text($0.title).tag(Optional($0)) }
            }
            .labelsHidden()
            hint("在光标当前位置点击。")
        case .scroll:
            let current: ScrollAction = { if case .scroll(let value) = action { return value }; return .init() }()
            Picker("滚动方向", selection: Binding(get: {
                if case .scroll(let value) = action { return Optional(value.direction) }; return nil
            }, set: { if let direction = $0 { var value = current; value.direction = direction; save(.scroll(value)) } })) {
                Text("选择方向").tag(nil as ScrollAction.Direction?)
                ForEach(ScrollAction.Direction.allCases) { Text($0.title).tag(Optional($0)) }
            }
            .labelsHidden()
            HStack {
                Text("滚动距离").font(RimoStyle.label)
                Slider(value: Binding(get: { Double(current.boundedAmount) }, set: {
                    var value = current; value.amount = Int($0); save(.scroll(value))
                }), in: 10...600, step: 10)
                Text("\(current.boundedAmount) px").font(RimoStyle.label).monospacedDigit().frame(width: 55)
            }
            hint("每次触发滚动一次，作用于光标所在区域。")
        case .media:
            if !inSidebar {
                Picker("媒体动作", selection: Binding(get: {
                    if case .media(let value) = action { return Optional(value) }; return nil
                }, set: { if let value = $0 { save(.media(value)) } })) {
                    Text("选择媒体动作").tag(nil as MediaAction?)
                    ForEach(MediaAction.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .labelsHidden()
                hint("控制系统当前的媒体播放或输出音量。")
            }
        case .system:
            if !inSidebar {
                Picker("系统操作", selection: Binding(get: {
                    if case .system(let value) = action { return Optional(value) }; return nil
                }, set: { if let value = $0 { save(.system(value)) } })) {
                    Text("选择系统操作").tag(nil as SystemAction?)
                    ForEach(SystemAction.allCases) { item in
                        Group {
                            if let restriction = assignmentRestriction(for: .system(item)) {
                                Label("\(item.title)（\(restriction)）", systemImage: "exclamationmark.triangle")
                                    .disabled(true)
                            } else {
                                Text(item.title)
                            }
                        }
                        .tag(Optional(item))
                    }
                }
                .labelsHidden()
            }
            if let restriction = assignmentRestriction(for: action) {
                hint("\(restriction)。请为这个方向键选择其他动作。")
            } else if action == .system(.toggleScrollMode) {
                hint("触发后用四个方向键滚动。以相同方式再次触发即可恢复原映射，也可从菜单栏关闭。")
            } else if action == .system(.activateSiri) {
                hint("请先在 macOS 系统设置中启用 Siri。")

            } else if !inSidebar || action != nil {
                hint(SystemAction.otherActions.contains { action == .system($0) }
                     ? "使用 macOS 常用快捷键，前台 App 需要支持对应操作。"
                     : "请确认 macOS 已启用相应的系统快捷键。")
            }
        case .openApp:
            let app: AppTarget? = { if case .openApp(let value) = action { return value }; return nil }()
            let editingTrigger = trigger
            OpenApplicationFields(selection: app) { target in
                guard kind.wrappedValue == .openApp, trigger == editingTrigger else { return false }
                return model.setAction(target.map(RemoteAction.openApp), for: button, trigger: trigger, sceneID: sceneID)
            }
            .id(editingTrigger)
        case .text:
            TextEditor(text: $draftText)
                .font(RimoStyle.body)
                .frame(minHeight: 90, maxHeight: 130)
                .padding(8)
                .overlay { RimoStyle.controlShape.strokeBorder(RimoStyle.line).allowsHitTesting(false) }
                .accessibilityLabel("预设文本")
                .onChange(of: draftText) { value in
                    if value.count > 4000 { draftText = String(value.prefix(4000)) }
                }
            Toggle("输入后按回车", isOn: $draftReturn)
                .toggleStyle(.checkbox)
            HStack {
                Text("\(draftText.count) / 4000").font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
                Spacer()
                Button(textDraftSaved ? "已保存" : "保存文本") { save(.text(.init(value: draftText, appendReturn: draftReturn))) }
                    .buttonStyle(RimoButtonStyle(primary: true))
                    .disabled(draftText.isEmpty || textDraftSaved)
            }
            hint("触发时输入到前台 App 的当前输入位置。")
        }
    }

    private var textDraftSaved: Bool {
        if case .text(let text) = action { return text.value == draftText && text.appendReturn == draftReturn }
        return false
    }

    private func loadTextDraft() {
        if case .text(let text) = action { draftText = text.value; draftReturn = text.appendReturn }
        else { draftText = ""; draftReturn = false }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var keyboardBehavior: some View {
        if let keyboard {
            if trigger != .doublePress {
                Picker("发送方式", selection: Binding(get: { keyboard.holdsUntilRelease == true }, set: { held in
                    var value = keyboard; value.holdsUntilRelease = held; save(.keyboard(value))
                })) {
                    Text("触发一次").tag(false)
                    Text("按住至松开").tag(true)
                }
                hint(keyboard.holdsUntilRelease == true
                     ? (trigger == .hold ? "按住半秒后保持按下，遥控器松开时释放。" : "按下即保持，遥控器松开时释放；此方式不使用双击和长按配置。")
                     : "发送一次完整的按下与松开。")
            }
            DisclosureGroup("修饰键位置") {
                ForEach([kVK_Command, kVK_Option, kVK_Control, kVK_Shift], id: \.self) { code in
                    modifierSide(UInt16(code), keyboard: keyboard)
                }
            }
            .font(RimoStyle.label)
        }
    }

    private func modifierSide(_ left: UInt16, keyboard: KeyboardShortcut) -> some View {
        let right: UInt16 = [UInt16(kVK_Command): UInt16(kVK_RightCommand), UInt16(kVK_Option): UInt16(kVK_RightOption),
                            UInt16(kVK_Control): UInt16(kVK_RightControl), UInt16(kVK_Shift): UInt16(kVK_RightShift)][left]!
        let flag = KeyboardShortcut.modifierFlag(for: left)!
        return Picker(KeyboardShortcut.navigationKeys.first { $0.id == left }!.title.replacingOccurrences(of: "左 ", with: ""),
                      selection: Binding(get: { keyboard.modifierKeyCodes?.contains(right) == true }, set: { useRight in
            var value = keyboard
            var codes = value.modifierKeyCodes ?? []
            codes.removeAll { KeyboardShortcut.modifierFlag(for: $0) == flag }
            codes.append(useRight ? right : left)
            value.modifierKeyCodes = codes
            save(.keyboard(value))
        })) {
            Text("左侧").tag(false)
            Text("右侧").tag(true)
        }
        .disabled(!flags.contains(flag) || editingRecording)
    }

    private var flags: NSEvent.ModifierFlags {
        keyboard.map { NSEvent.ModifierFlags(rawValue: UInt($0.modifiers)) } ?? draftFlags
    }

    private func modifier(_ icon: String, _ title: String, _ flag: NSEvent.ModifierFlags) -> some View {
        let active = flags.contains(flag)
        return Button {
            var modified = flags
            if active { modified.remove(flag) } else { modified.insert(flag) }
            recordingFeedback = nil
            if let keyboard {
                model.setAction(.keyboard(keyboard.updating(flags: modified)), for: button, trigger: trigger, sceneID: sceneID)
            }
            draftFlags = modified
        } label: {
            Group { if icon == "fn" { Text("fn") } else { Image(systemName: icon) } }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(RimoStyle.ink)
                .background(active ? RimoStyle.line : RimoStyle.surface, in: RimoStyle.controlShape)
                .overlay {
                    RimoStyle.controlShape
                        .strokeBorder(active ? RimoStyle.muted : RimoStyle.line)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
        .disabled(editingRecording)
    }

    private var keySelection: Binding<UInt16?> {
        Binding(get: { keyboard?.keyCode }, set: { code in
            recordingFeedback = nil
            if let key = KeyboardShortcut.navigationKeys.first(where: { $0.id == code }) {
                var shortcut = KeyboardShortcut(option: key, flags: flags)
                shortcut.holdsUntilRelease = keyboard?.holdsUntilRelease
                shortcut.modifierKeyCodes = keyboard?.modifierKeyCodes
                model.setAction(.keyboard(shortcut), for: button, trigger: trigger, sceneID: sceneID)
            } else if code == nil, keyboard != nil {
                model.setAction(nil, for: button, trigger: trigger, sceneID: sceneID)
            }
        })
    }

    private func stopCapture() {
        if editingRecording {
            recordingState = .idle
            model.cancelRecording()
        }
    }

    private struct ActionRowID: Hashable {
        let group: ActionGroup
        let choice: ActionChoice
    }

    private enum ActionGroup: String, CaseIterable, Identifiable {
        case recommended, keyboard, media, windows, system, apps, other
        var id: Self { self }
        var title: String {
            switch self {
            case .recommended: "推荐"
            case .keyboard: "键盘"
            case .media: "媒体与音量"
            case .windows: "窗口与桌面"
            case .system: "系统操作"
            case .apps: "应用与快捷指令"
            case .other: "其他动作"
            }
        }
    }

    private enum ActionChoice: Hashable, Identifiable {
        case configure(EditorKind), saved(SavedAction), key(UInt16), scroll(ScrollAction.Direction), media(MediaAction), mouse(MouseAction), system(SystemAction)

        static let presetKeyCodes = KeyboardShortcut.navigationKeys.map(\.id)
        var id: Self { self }

        var kind: EditorKind {
            switch self {
            case .configure(let kind): kind
            case .saved(let saved): EditorKind(action: saved.action)
            case .key: .keyboard
            case .scroll: .scroll
            case .media: .media
            case .mouse: .mouse
            case .system: .system
            }
        }

        var action: RemoteAction? {
            switch self {
            case .configure: nil
            case .saved(let saved): saved.action
            case .key(let code): KeyboardShortcut.navigationKeys.first { $0.id == code }
                .map { .keyboard(KeyboardShortcut(option: $0, flags: [])) }
            case .scroll(let direction): .scroll(.init(direction: direction))
            case .media(let item): .media(item)
            case .mouse(let item): .mouse(item)
            case .system(let item): .system(item)
            }
        }

        var title: String {
            switch self {
            case .key(let code):
                switch Int(code) {
                case kVK_Return: "回车"
                case kVK_Escape: "Esc / 退出"
                case kVK_Space: "空格"
                case kVK_Tab: "Tab / 制表键"
                case kVK_Delete: "Delete / 退格"
                case kVK_ForwardDelete: "Forward Delete / 向前删除"
                case kVK_ANSI_KeypadEnter: "Enter / 小键盘回车"
                case kVK_UpArrow: "向上方向键"
                case kVK_DownArrow: "向下方向键"
                case kVK_LeftArrow: "向左方向键"
                case kVK_RightArrow: "向右方向键"
                case kVK_PageUp: "向上翻页"
                case kVK_PageDown: "向下翻页"
                case kVK_Home: "Home / 开头"
                case kVK_End: "End / 末尾"
                default: action?.title ?? kind.title
                }
            case .scroll(let direction): direction.title
            default: action?.title ?? kind.title
            }
        }
        init(current: RemoteAction) {
            switch current {
            case .keyboard(let key) where key.modifiers == 0 && key.holdsUntilRelease != true
                && (key.modifierKeyCodes ?? []).isEmpty && Self.presetKeyCodes.contains(key.keyCode):
                self = .key(key.keyCode)
            case .scroll(let value): self = .scroll(value.direction)
            case .media(let item): self = .media(item)
            case .mouse(let item): self = .mouse(item)
            case .system(let item): self = .system(item)
            default: self = .saved(SavedAction(action: current))
            }
        }

        func represents(_ current: RemoteAction) -> Bool {
            switch self {
            case .configure: return false
            case .saved(let saved): return saved.action.matchesBinding(current)
            case .scroll(let direction):
                if case .scroll(let value) = current { return value.direction == direction }
                return false
            case .key(let code):
                if case .keyboard(let key) = current {
                    return key.keyCode == code && key.modifiers == 0 && key.holdsUntilRelease != true
                        && (key.modifierKeyCodes ?? []).isEmpty
                }
                return false
            default: return action == current
            }
        }

        func matches(_ query: String) -> Bool {
            let query = query.filter { !$0.isWhitespace }
            return ([title, kind.title] + searchAliases).contains { name in
                name.filter { !$0.isWhitespace }.localizedStandardContains(query)
            }
        }

        private var searchAliases: [String] {
            switch self {
            case .configure(.openApp): ["打开应用程序"]
            case .configure(.keyboard): ["自定义"]
            case .media(.nextTrack): ["下一首"]
            case .media(.previousTrack): ["上一首"]
            case .media(.volumeUp): ["增大音量"]
            case .media(.volumeDown): ["减小音量"]
            case .system(.appWindows): ["当前 App 的全部窗口"]
            case .system(.previousDesktop): ["上一个桌面"]
            case .system(.nextDesktop): ["下一个桌面"]
            case .system(.showDesktop): ["显示桌面", "隐藏桌面"]
            case .system(.lockScreen): ["锁定屏幕", "锁屏"]
            case .system(.activateSiri): ["唤醒 Siri"]
            case .system(.back): ["网页后退"]
            case .system(.forward): ["网页前进"]
            case .system(.newTab): ["新建标签页"]
            case .system(.zoomIn): ["放大页面"]
            case .system(.zoomOut): ["缩小页面"]
            case .system(.resetZoom): ["重置页面缩放"]
            case .system(.captureScreen): ["全屏截屏"]
            case .system(.emoji): ["表情与符号"]
            default: []
            }
        }
    }

    private struct SavedAction: Hashable {
        let action: RemoteAction
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.action == rhs.action }
        func hash(into hasher: inout Hasher) { hasher.combine(action.title) }
    }

    private enum EditorKind: String, Hashable, CaseIterable, Identifiable {
        case keyboard, mouse, scroll, media, system, openApp, text, shortcut
        var id: Self { self }
        var title: String {
            switch self {
            case .keyboard: "键盘快捷键"
            case .mouse: "鼠标点击"
            case .scroll: "滚动"
            case .media: "媒体控制"
            case .system: "系统操作"
            case .openApp: "打开 App"
            case .text: "输入文本"
            case .shortcut: "运行快捷指令"
            }
        }
        init(action: RemoteAction?) {
            switch action {
            case .keyboard, nil: self = .keyboard
            case .mouse: self = .mouse
            case .scroll: self = .scroll
            case .media: self = .media
            case .system: self = .system
            case .openApp: self = .openApp
            case .text: self = .text
            case .shortcut: self = .shortcut
            }
        }
    }
    private enum RecordingState: Equatable {
        case idle, listening(NSEvent.ModifierFlags), review(KeyboardShortcut)
    }
}

private struct OpenApplicationFields: View {
    let selection: AppTarget?
    let save: (AppTarget?) -> Bool
    @State private var draftPath: String?
    @State private var error: String?
    @State private var browsing = false
    @FocusState private var pathFocused: Bool

    private var savedPath: String { selection?.path ?? selection?.installedURL?.path ?? "" }
    private var pathInput: Binding<String> {
        Binding(get: { draftPath ?? savedPath }, set: { draftPath = $0; error = nil })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("应用程序路径", text: pathInput,
                      prompt: Text("输入应用程序路径").foregroundColor(RimoStyle.muted))
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RimoStyle.surface, in: RimoStyle.controlShape)
                .overlay {
                    RimoStyle.controlShape.strokeBorder(pathFocused ? RimoStyle.assignmentAccent : RimoStyle.line)
                        .allowsHitTesting(false)
                }
                .focused($pathFocused)
                .onSubmit { pathFocused = false }
                .onChange(of: pathFocused) { focused in
                    if !focused && !browsing { applyPath() }
                }

            Button(action: browse) {
                Text("浏览应用程序")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RimoStyle.actionConfigurationLink)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 32)
            }
            .buttonStyle(ActionBrowserRowStyle())
            .disabled(browsing)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(RimoStyle.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: selection) { _ in
            draftPath = nil
            error = nil
        }
    }

    private func applyPath() {
        guard let draftPath else { return }
        let value = draftPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != savedPath else { self.draftPath = nil; return }
        if value.isEmpty {
            if save(nil) { self.draftPath = nil }
            return
        }
        let absolutePath = (value as NSString).expandingTildeInPath
        guard absolutePath.hasPrefix("/") else {
            error = "请输入应用程序的完整路径，或点按「浏览应用程序」。"
            return
        }
        apply(URL(fileURLWithPath: absolutePath))
    }

    private func browse() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.applicationBundle]
        picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        picker.prompt = "打开"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        browsing = true
        let finished: (NSApplication.ModalResponse) -> Void = { result in
            browsing = false
            guard result == .OK, let url = picker.url else { return }
            apply(url)
        }
        if let window = NSApp.keyWindow {
            picker.beginSheetModal(for: window, completionHandler: finished)
        } else {
            picker.begin(completionHandler: finished)
        }
    }

    private func apply(_ url: URL) {
        guard let target = AppTarget.at(url) else {
            error = "找不到有效的应用程序。请输入 .app 路径，或点按「浏览应用程序」。"
            return
        }
        guard save(target) else { return }
        draftPath = nil
        error = nil
    }
}

/// A single visible glyph unfolds into a three-position rail. The rail is
/// translated, rather than rebuilt, so the selected glyph survives collapse.
private struct ActionTriggerPicker: View {
    let selection: RemoteTrigger
    let assigned: Bool
    let actionTitle: String
    let unavailable: Set<RemoteTrigger>
    let select: (RemoteTrigger) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: RemoteTrigger?
    @State private var hovering = false

    private let step: CGFloat = 32
    private var open: Bool { hovering || focused != nil }
    private var index: Int { RemoteTrigger.allCases.firstIndex(of: selection) ?? 0 }

    private var rail: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(assigned ? RimoStyle.assignmentAccent : RimoStyle.line)
                .frame(width: 28, height: 26)
                .offset(x: CGFloat(index) * step + 2)
                .allowsHitTesting(false)
            HStack(spacing: 4) {
                ForEach(RemoteTrigger.allCases) { mode in
                    Button { select(mode) } label: {
                        glyph(mode)
                            .foregroundStyle(assigned && selection == mode ? RimoStyle.assignmentInk : RimoStyle.ink)
                            .opacity(unavailable.contains(mode) ? 0.3 : 1)
                            .frame(width: 28, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focused, equals: mode)
                    .disabled(unavailable.contains(mode))
                    .allowsHitTesting(open || mode == selection)
                    .accessibilityHidden(!open && mode != selection)
                    .accessibilityLabel("\(actionTitle)，\(mode.title)")
                    .accessibilityValue(assigned && selection == mode ? "已绑定" : "未绑定")
                    .accessibilityAddTraits(assigned && selection == mode ? .isSelected : [])
                    .help(unavailable.contains(mode) ? "单击使用按住至松开，暂不识别\(mode.title)" : "\(mode.title) · 点击绑定")
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 96, height: 30, alignment: .leading)
    }

    var body: some View {
        Color.clear
        .frame(width: open ? 96 : 32, height: 30)
        .overlay(alignment: .leading) {
            rail.offset(x: open ? 0 : -CGFloat(index) * step)
        }
        .background(RimoStyle.canvas, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focused != nil ? RimoStyle.assignmentAccent : .clear)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: open)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selection)
        .onHover {
            hovering = $0
            if !$0 { focused = nil }
        }
        .frame(width: 100, alignment: .trailing)
    }

    @ViewBuilder private func glyph(_ mode: RemoteTrigger) -> some View {
        switch mode {
        case .single: Circle().frame(width: 4, height: 4)
        case .doublePress:
            HStack(spacing: 4) {
                Circle().frame(width: 4, height: 4)
                Circle().frame(width: 4, height: 4)
            }
        case .hold: Capsule().frame(width: 13, height: 3)
        }
    }
}

private struct ActionBrowserRowStyle: ButtonStyle {
    var current = false
    var expanded = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, current: current, expanded: expanded)
    }

    private struct Row: View {
        let configuration: Configuration
        let current: Bool
        let expanded: Bool
        @State private var hovered = false
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .background {
                    if expanded {
                        GeometryReader { geometry in
                            Path(roundedRect: CGRect(origin: .zero, size: CGSize(width: geometry.size.width,
                                                                                 height: geometry.size.height + 8)),
                                 cornerRadius: 8)
                                .fill(RimoStyle.assignmentAccent)
                        }
                        .clipped()
                    } else {
                        RimoStyle.controlShape.fill(
                            current ? RimoStyle.assignmentAccent
                                : enabled && (hovered || configuration.isPressed) ? RimoStyle.assignmentAccent.opacity(0.08) : .clear
                        )
                    }
                }
                .overlay {
                    RimoStyle.controlShape.strokeBorder(focused ? RimoStyle.assignmentAccent : .clear)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}

extension RemoteButton {
    var glyph: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left, .back: "chevron.left"
        case .right: "chevron.right"
        case .select: "circle.circle"
        case .menu: "list.bullet"
        case .home: "tv"
        case .playPause: "playpause"
        case .mute: "speaker.slash"
        case .volumeUp: "plus"
        case .volumeDown: "minus"
        case .power: "power"
        case .siri: "mic"
        }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    var onShortcut: (KeyboardShortcut) -> Void
    var onModifiers: (NSEvent.ModifierFlags) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.update(from: self)
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak view, weak coordinator] event in
            guard let coordinator, coordinator.isListening,
                  let window = view?.window, window.isKeyWindow, event.window === window else { return event }
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
                if let flag = KeyboardShortcut.modifierFlag(for: event.keyCode), flags.contains(flag) {
                    coordinator.lastModifier = event.keyCode
                } else if flags.isEmpty, let code = coordinator.lastModifier,
                          let option = KeyboardShortcut.navigationKeys.first(where: { $0.id == code }) {
                    coordinator.isListening = false
                    coordinator.onShortcut?(KeyboardShortcut(option: option, flags: []))
                }
                coordinator.onModifiers?(flags)
                return nil
            }
            if !event.isARepeat {
                if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection([.command, .option, .shift, .control]).isEmpty {
                    coordinator.isListening = false
                    coordinator.onCancel?()
                } else if let shortcut = KeyboardShortcut(event: event) {
                    // Modifier releases may arrive before SwiftUI removes the monitor.
                    coordinator.isListening = false
                    coordinator.onShortcut?(shortcut)
                }
            }
            return nil
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { context.coordinator.update(from: self) }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    final class Coordinator {
        var monitor: Any?
        var isListening = true
        var lastModifier: UInt16?
        var onShortcut: ((KeyboardShortcut) -> Void)?
        var onModifiers: ((NSEvent.ModifierFlags) -> Void)?
        var onCancel: (() -> Void)?

        @MainActor func update(from capture: ShortcutCapture) {
            onShortcut = capture.onShortcut
            onModifiers = capture.onModifiers
            onCancel = capture.onCancel
        }
    }
}
