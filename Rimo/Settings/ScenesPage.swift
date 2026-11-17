import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScenesPage: View {
    @ObservedObject var model: RimoModel
    let openDeviceSettings: () -> Void
    @State private var sheet: SceneSheet?
    @State private var editAfterDismissal: AppSceneMapping?
    @State private var deleting: AppSceneMapping?
    @State private var feedback: SceneFeedback?

    private enum SceneSheet: Identifiable {
        case add, presets, edit(AppSceneMapping)

        var id: String {
            switch self {
            case .add: "add"
            case .presets: "presets"
            case .edit(let scene): "edit:\(scene.id)"
            }
        }
    }

    private struct SceneFeedback {
        let title: String
        var isError = false
        var needsAutomaticSwitching = false
    }

    var body: some View {
        SettingsScroll {
            HStack {
                Text("场景").font(RimoStyle.heading)
                    .tracking(RimoStyle.headingTracking)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { sheet = .presets } label: {
                    Label("场景预设", systemImage: "square.grid.2x2")
                }
                .buttonStyle(RimoButtonStyle())
                Button { sheet = .add } label: {
                    Label("添加场景", systemImage: "plus")
                }
                .buttonStyle(RimoButtonStyle(primary: true))
            }
            if let feedback {
                let hint = feedback.needsAutomaticSwitching && !model.configuration.automatic ? " 开启自动切换后生效。" : ""
                Label(feedback.title + hint, systemImage: feedback.isError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(RimoStyle.prose)
                    .foregroundStyle(RimoStyle.ink)
            }

            if !model.canListen || !model.canPost {
                permissionNotice
            }

            currentSceneCard

            SettingsCard {
                if model.configuration.scenes.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 23))
                            .foregroundStyle(RimoStyle.ink)
                            .frame(width: 48, height: 48)
                            .background(RimoStyle.canvas, in: RimoStyle.controlShape)
                        Text("还没有场景").font(RimoStyle.title)
                        Text("从预设开始，或为一个 App 自定义遥控器按键。")
                            .font(RimoStyle.prose)
                            .foregroundStyle(RimoStyle.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.configuration.scenes) { scene in
                            sceneRow(scene)
                            if scene.id != model.configuration.scenes.last?.id {
                                RimoDivider().padding(.leading, 62)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $sheet, onDismiss: {
            if let scene = editAfterDismissal {
                editAfterDismissal = nil
                sheet = .edit(scene)
            }
        }) { item in
            switch item {
            case .add:
                AppScenePicker(excluded: Set(model.configuration.scenes.map(\.id))) { app in
                    feedback = nil
                    if model.addScene(id: app.id, name: app.name) {
                        editAfterDismissal = model.scene(app.id)
                    } else {
                        feedback = .init(title: model.configurationError ?? "这个 App 已有场景。", isError: true)
                    }
                }
            case .presets:
                ScenePresetPicker(model: model) { preset, app in
                    feedback = .init(title: "已将「\(preset.title)」应用到「\(app.name)」。", needsAutomaticSwitching: true)
                }
            case .edit(let scene):
                SceneEditor(model: model, sceneID: scene.id, name: scene.name)
            }
        }
        .alert("删除场景？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) {
                if let deleting { model.removeScene(id: deleting.id) }
                deleting = nil
            }
        } message: {
            Text("删除后，「\(deleting?.name ?? "")」会使用全局映射。")
        }
    }

    private var permissionNotice: some View {
        let detail = switch (model.canListen, model.canPost) {
        case (false, false): "允许「输入监控」读取遥控器，并允许「辅助功能」发送键盘快捷键。"
        case (false, true): "允许「输入监控」后，Rimo 才能读取遥控器按键。"
        case (true, false): "允许「辅助功能」后，Rimo 才能发送键盘快捷键。"
        case (true, true): ""
        }
        return SettingsCard {
            HStack(spacing: RimoStyle.elementGap) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("按键映射需要系统授权", systemImage: "exclamationmark.triangle")
                        .font(RimoStyle.title)
                    Text(detail)
                        .font(RimoStyle.prose)
                        .foregroundStyle(RimoStyle.muted)
                }
                Spacer()
                Button("设备设置", action: openDeviceSettings)
                    .fixedSize()
            }
            .padding(RimoStyle.cardPadding)
        }
    }

    private var currentSceneCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: RimoStyle.elementGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("根据前台 App 自动切换映射")
                            .font(RimoStyle.title)
                        Text("某个 App 在最前面时，自动套用它的映射规则。")
                            .font(RimoStyle.prose)
                            .foregroundStyle(RimoStyle.muted)
                    }
                    Spacer()
                    Toggle("根据前台 App 自动切换映射",
                           isOn: Binding(get: { model.configuration.automatic }, set: model.setAutomaticScenes))
                        .labelsHidden()
                        .toggleStyle(RimoPillSwitch())
                }
                RimoDivider()
                HStack(spacing: 8) {
                    Label("当前前台：", systemImage: "macwindow")
                        .foregroundStyle(RimoStyle.muted)
                    Text(model.frontmostApp?.localizedName ?? "—").fontWeight(.semibold)
                    Spacer()
                    Text(model.activeScene?.name ?? "默认映射")
                        .foregroundStyle(RimoStyle.muted)
                }
                .font(RimoStyle.label)
            }
            .padding(RimoStyle.cardPadding)
        }
    }

    private func sceneRow(_ scene: AppSceneMapping) -> some View {
        HStack(spacing: 12) {
            SceneAppIcon(id: scene.id)
            VStack(alignment: .leading, spacing: 3) {
                Text(scene.name).font(RimoStyle.title)
                Text(scene.id).font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button("编辑") { sheet = .edit(scene) }
                .accessibilityLabel("编辑\(scene.name)的场景")
            Toggle("启用\(scene.name)的场景", isOn: Binding(get: { scene.enabled }, set: { model.setSceneEnabled($0, id: scene.id) }))
                .labelsHidden()
                .toggleStyle(RimoPillSwitch(width: 35, height: 16))
            Button { deleting = scene } label: { Image(systemName: "trash") }
                .accessibilityLabel("删除\(scene.name)的场景")
        }
        .padding(.horizontal, RimoStyle.cardPadding)
        .frame(minHeight: 60)
    }
}

struct AppScenePicker: View {
    @Environment(\.dismiss) private var dismiss
    let excluded: Set<String>
    let onSelect: (SceneTargetApp) -> Void
    @State private var invalid = false
    @State private var browsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("添加场景").font(RimoStyle.heading).tracking(RimoStyle.headingTracking)
            Text("选择一个正在运行的 App，或从应用程序文件夹中选择。")
                .font(RimoStyle.prose)
                .foregroundStyle(RimoStyle.muted)
            SceneAppList(excluded: excluded, onSelect: select).frame(height: 220)
            HStack {
                Button("浏览应用程序…") { browsing = true }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if invalid { Label("请选择一个还没有场景的 Mac App。", systemImage: "exclamationmark.triangle") }
        }
        .padding(22)
        .frame(width: 460)
        .background(RimoStyle.canvas)
        .foregroundStyle(RimoStyle.ink)
        .buttonStyle(RimoButtonStyle())
        .fileImporter(isPresented: $browsing, allowedContentTypes: [.applicationBundle]) { result in
            guard case .success(let url) = result else { return }
            guard let app = SceneTargetApp(url: url), !excluded.contains(app.id) else {
                invalid = true
                return
            }
            select(app)
        }
    }

    private func select(_ app: SceneTargetApp) {
        onSelect(app)
        dismiss()
    }
}

struct SceneTargetApp: Identifiable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init?(url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        self.init(id: id, name: name)
    }
}

private struct SceneAppList: View {
    var excluded: Set<String> = []
    var existing: Set<String> = []
    let onSelect: (SceneTargetApp) -> Void

    private var applications: [SceneTargetApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, !excluded.contains(id),
                  let name = app.localizedName, seen.insert(id).inserted else { return nil }
            return SceneTargetApp(id: id, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let apps = applications
        if apps.isEmpty {
            Text("没有可选的运行中 App，可浏览应用程序文件夹。")
                .font(RimoStyle.prose)
                .foregroundStyle(RimoStyle.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(apps) { app in
                Button { onSelect(app) } label: {
                    HStack {
                        SceneAppIcon(id: app.id, size: 25)
                        Text(app.name)
                        Spacer()
                        if existing.contains(app.id) {
                            Text("已有场景").font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ScenePresetPicker: View {
    @ObservedObject var model: RimoModel
    let onApply: (ScenePreset, SceneTargetApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preset = ScenePreset.presentation
    @State private var step = Step.templates
    @State private var browsing = false
    @State private var error: String?

    private enum Step {
        case templates, apps, review(SceneTargetApp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch step {
            case .templates:
                heading("场景预设", subtitle: "选一套常用按键，再把它应用到一个 App。")
                HStack(spacing: 8) {
                    ForEach(ScenePreset.allCases) { candidate in
                        Button { preset = candidate } label: {
                            Label(candidate.title, systemImage: candidate.symbol)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RimoButtonStyle(primary: preset == candidate))
                        .accessibilityAddTraits(preset == candidate ? .isSelected : [])
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(preset.detail).font(RimoStyle.prose).foregroundStyle(RimoStyle.muted)
                    bindings()
                }
                .frame(minHeight: 190, alignment: .top)
                HStack {
                    cancel
                    Spacer()
                    Button("选择 App…") { step = .apps }
                        .buttonStyle(RimoButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                }
            case .apps:
                heading("选择 App", subtitle: "将「\(preset.title)」用于一个 App。每个 App 只有一个场景。")
                SceneAppList(existing: Set(model.configuration.scenes.map(\.id)), onSelect: select)
                    .frame(height: 232)
                if let error { errorMessage(error) }
                HStack {
                    back(to: .templates)
                    Button("浏览应用程序…") { browsing = true }
                    Spacer()
                    cancel
                }
            case .review(let app):
                let existing = model.scene(app.id)
                heading("确认应用预设", subtitle: "查看选定 App 将使用的按键。")
                HStack(spacing: 10) {
                    SceneAppIcon(id: app.id)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(RimoStyle.title)
                        Text(preset.title).font(RimoStyle.prose).foregroundStyle(RimoStyle.muted)
                    }
                    Spacer()
                }
                bindings(comparingWith: existing?.resolved(global: model.configuration.global) ?? model.configuration.global,
                         scene: existing)
                VStack(alignment: .leading, spacing: 5) {
                    if existing == nil {
                        Text("未列出的按键跟随全局映射。")
                    } else {
                        Text("只替换并启用上面列出的按键；其余按键保持原样。")
                    }
                    if preset == .webVideo {
                        Text("如果选择浏览器，场景会对它的所有标签页生效。")
                    }
                    if existing?.enabled == false {
                        Text("这个场景已停用，启用后才会生效。")
                    }
                    if !model.configuration.automatic {
                        Text("自动切换已关闭，开启后才会使用场景映射。")
                    }
                }
                .font(RimoStyle.prose)
                .foregroundStyle(RimoStyle.muted)
                if let error { errorMessage(error) }
                HStack {
                    back(to: .apps)
                    Spacer()
                    cancel
                    Button("应用预设") {
                        if model.applyPreset(preset, id: app.id, name: app.name) {
                            onApply(preset, app)
                            dismiss()
                        } else {
                            error = model.configurationError ?? "未能保存场景，请重试。"
                        }
                    }
                    .buttonStyle(RimoButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(RimoStyle.canvas)
        .foregroundStyle(RimoStyle.ink)
        .buttonStyle(RimoButtonStyle())
        .fileImporter(isPresented: $browsing, allowedContentTypes: [.applicationBundle]) { result in
            guard case .success(let url) = result else { return }
            guard let app = SceneTargetApp(url: url) else {
                error = "请选择一个其他的 Mac App。"
                return
            }
            select(app)
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(RimoStyle.heading).tracking(RimoStyle.headingTracking)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(RimoStyle.prose).foregroundStyle(RimoStyle.muted)
        }
    }

    private func bindings(comparingWith current: ButtonMappings? = nil, scene: AppSceneMapping? = nil) -> some View {
        SettingsCard {
            VStack(spacing: 0) {
                ForEach(preset.bindings) { binding in
                    HStack(spacing: 9) {
                        Image(systemName: binding.button.glyph).frame(width: 16)
                            .accessibilityHidden(true)
                        Text(binding.button.title).frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(binding.purpose)
                            if let current, let previous = previousMapping(for: binding, current: current, scene: scene) {
                                Text(previous).font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
                            }
                        }
                        Spacer()
                        RimoKeycap(title: binding.shortcut.title)
                    }
                    .font(RimoStyle.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                    if binding.id != preset.bindings.last?.id {
                        RimoDivider().padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    private func previousMapping(for binding: ScenePreset.Binding, current: ButtonMappings, scene: AppSceneMapping?) -> String? {
        let action = current[binding.button]
        let enabled = current.isEnabled(binding.button)
        guard !enabled || (action != nil && action != binding.action) else { return nil }
        let origin = (scene?.inherits(binding.button) ?? true) ? "全局映射" : "原映射"
        return "\(origin)：\(action?.title ?? "未设置")\(enabled ? "" : "（已停用）")"
    }

    private var cancel: some View {
        Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
    }

    private func back(to previous: Step) -> some View {
        Button("上一步") {
            error = nil
            step = previous
        }
    }

    private func errorMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle").font(RimoStyle.prose)
    }

    private func select(_ app: SceneTargetApp) {
        error = nil
        step = .review(app)
    }
}

private struct SceneEditor: View {
    @ObservedObject var model: RimoModel
    let sceneID: String
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var selected: RemoteButton?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SceneAppIcon(id: sceneID)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(RimoStyle.heading).tracking(RimoStyle.headingTracking)
                    Text("这个 App 在前台时的映射").foregroundStyle(RimoStyle.muted)
                        .font(RimoStyle.prose)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(RimoButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            if let error = model.configurationError { Label(error, systemImage: "exclamationmark.triangle") }
            RimoDivider()
            HStack(alignment: .top, spacing: 20) {
                ScrollView {
                    let buttons = model.mappings(sceneID: sceneID)
                    let scene = model.scene(sceneID)
                    VStack(spacing: 2) {
                        ForEach(RemoteButton.a2540Buttons) { button in
                            Button { selected = button } label: {
                                HStack {
                                    Image(systemName: button.glyph).frame(width: 17)
                                    Text(button.title)
                                    Spacer()
                                    if RemoteTrigger.allCases.allSatisfy({ scene?.inherits(button, trigger: $0) == true }) {
                                        Text("全局").font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
                                    }
                                    Text(summary(for: button, in: buttons))
                                        .foregroundStyle(RimoStyle.muted).lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 29)
                                .background(selected == button ? RimoStyle.line : .clear, in: RimoStyle.controlShape)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected == button ? .isSelected : [])
                        }
                    }
                }
                .frame(width: 250)
                if let selected {
                    ScrollView {
                        ButtonMappingEditor(model: model, button: selected, sceneID: sceneID,
                                            close: { self.selected = nil }, openShortcuts: { model.loadShortcuts(force: true) })
                            .id(selected)
                            .padding(2)
                    }
                    .frame(width: 300)
                } else {
                    Text("选择一个按键来编辑它的映射")
                        .foregroundStyle(RimoStyle.muted)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(height: 420)
        }
        .padding(24)
        .background(RimoStyle.canvas)
        .foregroundStyle(RimoStyle.ink)
    }

    private func summary(for button: RemoteButton, in mappings: ButtonMappings) -> String {
        let additional = [RemoteTrigger.doublePress, .hold]
            .filter { mappings[button, $0] != nil && mappings.isEnabled(button, trigger: $0) }
            .map(\.title)
            .joined(separator: "、")
        if mappings.isEnabled(button), let single = mappings[button] {
            return additional.isEmpty ? single.title : "\(single.title) · \(additional)"
        }
        if !additional.isEmpty { return additional + "已设置" }
        return mappings.isEnabled(button) ? "未设置" : "已停用"
    }
}

private struct SceneAppIcon: View {
    let id: String
    var size: CGFloat = 31

    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app").resizable().foregroundStyle(RimoStyle.muted)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
