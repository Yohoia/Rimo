import AppKit
import Carbon.HIToolbox
import SwiftUI

struct MappingView: View {
    @ObservedObject var model: SofoModel
    @Binding var selected: RemoteButton?
    let openShortcuts: () -> Void

    @State private var recentlyPressed: RemoteButton?
    @State private var pressCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    fileprivate enum CardValue {
        case keycap(String)
        case detail(String)

        var label: String {
            switch self {
            case .keycap(let text), .detail(let text): text
            }
        }

        var isKeycap: Bool {
            if case .keycap = self { return true }
            return false
        }
    }

    private static let leadingButtons: [RemoteButton] = [.up, .left, .down, .back, .playPause, .mute]
    private static let trailingButtons: [RemoteButton] = [.power, .right, .select, .siri, .home, .volumeUp, .volumeDown]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let footerHeight: CGFloat = 54
            let bottomInset: CGFloat = 5
            let stageHeight = geometry.size.height - footerHeight - bottomInset
            let inset = width >= 1_000 ? 72.0 : 37.0
            let remoteGap = min(300, width * 0.29)
            let columnWidth = min(302, (width - inset * 2 - remoteGap) / 2)
            let remoteHeight = min(525, stageHeight - 34, (remoteGap - 20) / 0.44)
            // Lift the status into the available space without moving the stage or touching the remote.
            let footerLift = min(36, max(0, (stageHeight - remoteHeight) / 2 - 9))

            VStack(spacing: 0) {
                ZStack {
                    RemoteModelView(selected: selected, recentlyPressed: recentlyPressed, onSelect: select)
                        .frame(width: remoteHeight * 0.44, height: remoteHeight)

                    HStack(spacing: 0) {
                        cardColumn(Self.leadingButtons)
                            .frame(width: columnWidth)
                        Spacer(minLength: remoteGap)
                        cardColumn(Self.trailingButtons)
                            .frame(width: columnWidth)
                    }
                    .padding(.horizontal, inset)
                }
                .frame(maxWidth: .infinity)
                .frame(height: stageHeight)

                footer
                    .frame(height: footerHeight)
                    .padding(.bottom, bottomInset)
                    .offset(y: -footerLift)
            }
        }
        .onReceive(model.$lastButton.dropFirst()) { button in
            guard model.isSettingsFocused() else { return }
            recentlyPressed = button
            pressCount &+= 1
            if let button, model.recording == nil, RemoteButton.a2540Buttons.contains(button) { select(button) }
        }
        .task(id: pressCount) {
            try? await Task.sleep(for: .milliseconds(520))
            if !Task.isCancelled { recentlyPressed = nil }
        }
    }

    private func cardColumn(_ buttons: [RemoteButton]) -> some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: SofoStyle.elementGap) {
                        ForEach(buttons) { button in
                            Group {
                                if selected == button {
                                    ButtonMappingEditor(model: model, button: button, inline: true,
                                                        close: { select(nil) }, openShortcuts: openShortcuts)
                                } else {
                                    MappingCardSummary(button: button, value: summary(for: button)) { select(button) }
                                }
                            }
                            .id(button)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selected) { button in
                    guard let button, buttons.contains(button) else { return }
                    scroll.scrollTo(button, anchor: .center)
                }
            }
        }
    }

    private func summary(for button: RemoteButton) -> CardValue {
        if button == .siri && model.voice.enabled { return .detail("用于收音") }
        let mappings = model.mappings()
        guard mappings.isEnabled(button) else { return .detail("已停用") }
        switch mappings[button] {
        case .keyboard(let shortcut): return .keycap(shortcut.title)
        case .shortcut(let shortcut): return .detail(shortcut.name)
        case nil: return .detail("未设置")
        }
    }

    private func select(_ button: RemoteButton?) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: SofoStyle.stateDuration)) { selected = button }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(A2540Input.modelName)
                .font(SofoStyle.modelHeading)
                .tracking(1)
            HStack(spacing: 6) {
                SofoConnectionMark(connected: model.isRemoteConnected)
                Text(model.isRemoteConnected ? "已连接" : "未连接")
                    .font(SofoStyle.label)
                    .tracking(0.85)
                    .foregroundStyle(SofoStyle.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MappingCardSummary: View {
    let button: RemoteButton
    let value: MappingView.CardValue
    var select: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var detailColor: Color { hovering ? SofoStyle.ink : SofoStyle.muted }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Image(systemName: button.glyph)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 21)
                    .foregroundStyle(detailColor)
                    .accessibilityHidden(true)
                Text(button.title)
                    .font(SofoStyle.title)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 3)
                if value.isKeycap {
                    SofoKeycap(title: value.label)
                } else {
                    Text(value.label)
                        .font(SofoStyle.label)
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.forward")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(detailColor)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(hovering ? SofoStyle.line : SofoStyle.canvas, in: SofoStyle.controlShape)
            .modifier(SofoCardRings())
            .contentShape(SofoStyle.controlShape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: SofoStyle.stateDuration), value: hovering)
        .accessibilityLabel("映射卡片：\(button.title)")
        .accessibilityValue(value.label)
    }
}

private struct SofoKeycap: View {
    let title: String

    var body: some View {
        Text(title)
            .font(SofoStyle.label)
            .foregroundStyle(SofoStyle.ink)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(SofoStyle.surface, in: SofoStyle.controlShape)
            .overlay {
                SofoStyle.controlShape
                    .strokeBorder(SofoStyle.line)
                    .allowsHitTesting(false)
            }
    }
}

struct ButtonMappingEditor: View {
    @ObservedObject var model: SofoModel
    let button: RemoteButton
    var sceneID: String? = nil
    var inline = false
    let close: () -> Void
    let openShortcuts: () -> Void
    @State private var capturing = false
    @State private var hoveringRecord = false
    @State private var draftFlags: NSEvent.ModifierFlags = []
    @State private var kindOverride: EditorKind?

    private var mappings: ButtonMappings { model.mappings(sceneID: sceneID) }
    private var action: RemoteAction? { mappings[button] }
    private var keyboard: KeyboardShortcut? {
        if case .keyboard(let key) = action { return key }
        return nil
    }
    private var currentShortcut: SystemShortcut? {
        if case .shortcut(let shortcut) = action { return shortcut }
        return nil
    }
    private var reserved: Bool { button == .siri && model.voice.enabled }

    var body: some View {
        VStack(alignment: .leading, spacing: inline ? 12 : 16) {
            HStack(spacing: 8) {
                Image(systemName: button.glyph)
                    .font(.system(size: inline ? 15 : 20, weight: .semibold))
                    .foregroundStyle(SofoStyle.actionLabel)
                    .frame(width: inline ? 26 : 40, height: inline ? 28 : 40)
                    .background(SofoStyle.action, in: SofoStyle.controlShape)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(button.title).font(SofoStyle.title)
                    Text(reserved ? "用于遥控器收音" : action?.title ?? "未设置映射")
                        .font(SofoStyle.label)
                        .foregroundStyle(SofoStyle.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭按键编辑")
                .keyboardShortcut(.cancelAction)
            }

            SofoDivider()

            if reserved {
                Text("停止遥控器收音后，即可编辑 Siri 侧键。")
                    .foregroundStyle(SofoStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                configurationFields
            }
        }
        .font(SofoStyle.body)
        .padding(SofoStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SofoStyle.surface, in: SofoStyle.controlShape)
        .modifier(SofoCardRings())
        .overlay {
            SofoStyle.controlShape
                .strokeBorder(inline ? SofoStyle.muted : .clear)
                .allowsHitTesting(false)
        }
        .onDisappear(perform: stopCapture)
        .onChange(of: reserved) { if $0 { stopCapture() } }
        .background {
            if capturing {
                ShortcutCapture { shortcut in
                    model.setAction(.keyboard(shortcut), for: button, sceneID: sceneID)
                    stopCapture()
                } onCancel: {
                    stopCapture()
                }
            }
        }
    }

    private var configurationFields: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 4) {
                Text(inline ? "按键动作" : kind.wrappedValue == .keyboard ? "映射成快捷键" : "运行快捷指令")
                    .font(SofoStyle.label)
                    .foregroundStyle(SofoStyle.muted)
                Spacer()
                Picker("按键动作", selection: kind) {
                    Text("快捷键").tag(EditorKind.keyboard)
                    Text("运行快捷指令").tag(EditorKind.shortcut)
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            if kind.wrappedValue == .keyboard {
                recordField
                HStack(spacing: 7) {
                    modifier("command", "Command", .command)
                    modifier("option", "Option", .option)
                    modifier("control", "Control", .control)
                    modifier("shift", "Shift", .shift)
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
                .disabled(capturing)
            } else {
                shortcutPicker
            }

            HStack(spacing: 8) {
                Text("启用此按键")
                    .font(SofoStyle.label)
                Toggle("启用此按键", isOn: Binding(get: { mappings.isEnabled(button) }, set: {
                    model.setActionEnabled($0, for: button, sceneID: sceneID)
                }))
                .labelsHidden()
                .toggleStyle(SofoPillSwitch())
                Spacer(minLength: 0)
                if action != nil {
                    Button("清除") { model.setAction(nil, for: button, sceneID: sceneID) }
                        .buttonStyle(.borderless)
                        .disabled(capturing)
                }
            }
            .padding(.top, 4)
        }
    }

    private var recordField: some View {
        Button {
            if capturing { stopCapture() } else {
                model.startRecording(button)
                capturing = true
            }
        } label: {
            HStack(spacing: 6) {
                if capturing {
                    Circle().fill(SofoStyle.ink).frame(width: 7, height: 7)
                    Text("请按下快捷键")
                } else if let keyboard {
                    SofoKeycap(title: keyboard.title)
                } else {
                    Text("未录制").foregroundStyle(SofoStyle.muted)
                }
                Spacer(minLength: 6)
                Text(capturing ? "取消" : "点击录制")
                    .font(SofoStyle.body)
                    .foregroundStyle(capturing ? SofoStyle.ink : SofoStyle.actionLabel)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(capturing ? Color.clear : hoveringRecord ? SofoStyle.actionPressed : SofoStyle.action,
                                in: SofoStyle.controlShape)
            }
            .padding(.horizontal, 7)
            .frame(height: 33)
            .foregroundStyle(SofoStyle.ink)
            .background(SofoStyle.canvas, in: SofoStyle.controlShape)
            .overlay {
                SofoStyle.controlShape
                    .strokeBorder(capturing ? SofoStyle.ink : SofoStyle.line)
                    .allowsHitTesting(false)
            }
            .contentShape(SofoStyle.controlShape)
        }
        .buttonStyle(.plain)
        .onHover { hoveringRecord = $0 }
        .accessibilityLabel(capturing ? "取消录制" : "录制\(button.title)的快捷键")
        .accessibilityValue(keyboard?.title ?? "未录制")
        .accessibilityHint("按 Escape 取消；可从下方选择 Escape 作为映射。")
    }

    @ViewBuilder private var shortcutPicker: some View {
        let available = model.systemShortcuts
        VStack(alignment: .leading, spacing: 6) {
            if model.loadingShortcuts {
                ProgressView().controlSize(.small)
            } else if let error = model.shortcutListError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SofoStyle.ink).fixedSize(horizontal: false, vertical: true)
                Button("重新读取") { model.loadShortcuts(force: true) }
            } else if available.isEmpty {
                Text("没有可用的快捷指令").foregroundStyle(SofoStyle.muted)
                Button(action: openShortcuts) { Text("打开快捷指令页面").underline() }
                    .buttonStyle(.link)
                    .foregroundStyle(SofoStyle.ink)
            } else {
                Picker("选择快捷指令", selection: Binding(get: { currentShortcut?.id }, set: { id in
                    if let item = available.first(where: { $0.id == id }) {
                        model.setAction(.shortcut(item), for: button, sceneID: sceneID)
                    } else if currentShortcut != nil {
                        model.setAction(nil, for: button, sceneID: sceneID)
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

    private var kind: Binding<EditorKind> {
        Binding(get: { kindOverride ?? (currentShortcut == nil ? .keyboard : .shortcut) }, set: {
            stopCapture()
            kindOverride = $0
        })
    }

    private var flags: NSEvent.ModifierFlags {
        keyboard.map { NSEvent.ModifierFlags(rawValue: UInt($0.modifiers)) } ?? draftFlags
    }

    private func modifier(_ icon: String, _ title: String, _ flag: NSEvent.ModifierFlags) -> some View {
        let active = flags.contains(flag)
        return Button {
            var modified = flags
            if active { modified.remove(flag) } else { modified.insert(flag) }
            if let keyboard { model.setAction(.keyboard(keyboard.updating(flags: modified)), for: button, sceneID: sceneID) }
            draftFlags = modified
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: inline ? 27 : 35)
                .foregroundStyle(SofoStyle.ink)
                .background(active ? SofoStyle.line : SofoStyle.surface, in: SofoStyle.controlShape)
                .overlay {
                    SofoStyle.controlShape
                        .strokeBorder(active ? SofoStyle.muted : SofoStyle.line)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
        .disabled(capturing)
    }

    private var keySelection: Binding<UInt16?> {
        Binding(get: { keyboard?.keyCode }, set: { code in
            if let key = KeyboardShortcut.navigationKeys.first(where: { $0.id == code }) {
                let shortcut = KeyboardShortcut(option: key, flags: flags)
                model.setAction(.keyboard(shortcut), for: button, sceneID: sceneID)
            } else if code == nil, keyboard != nil {
                model.setAction(nil, for: button, sceneID: sceneID)
            }
        })
    }

    private func stopCapture() {
        if capturing {
            capturing = false
            model.cancelRecording()
        }
    }

    private enum EditorKind: Hashable { case keyboard, shortcut }
}

extension RemoteButton {
    static var a2540Buttons: [Self] {
        [.power, .up, .down, .left, .right, .select, .back, .home, .playPause, .volumeUp, .volumeDown, .mute, .siri]
    }

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
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.update(from: self)
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak view, weak coordinator] event in
            guard let window = view?.window, window.isKeyWindow, event.window === window else { return event }
            if !event.isARepeat {
                if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection([.command, .option, .shift, .control]).isEmpty {
                    coordinator?.onCancel?()
                } else if let shortcut = KeyboardShortcut(event: event) {
                    coordinator?.onShortcut?(shortcut)
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
        var onShortcut: ((KeyboardShortcut) -> Void)?
        var onCancel: (() -> Void)?

        @MainActor func update(from capture: ShortcutCapture) {
            onShortcut = capture.onShortcut
            onCancel = capture.onCancel
        }
    }
}
