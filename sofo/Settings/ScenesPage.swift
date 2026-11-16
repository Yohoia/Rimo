import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScenesPage: View {
    @ObservedObject var model: SofoModel
    @State private var choosingApp = false
    @State private var editing: AppSceneMapping?
    @State private var deleting: AppSceneMapping?
    @State private var addError: String?

    var body: some View {
        SettingsScroll {
            HStack {
                Text("场景").font(SofoStyle.heading)
                    .tracking(SofoStyle.headingTracking)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { choosingApp = true } label: {
                    Label("添加场景", systemImage: "plus")
                }
                .buttonStyle(SofoButtonStyle(primary: true))
            }
            if let addError { Label(addError, systemImage: "exclamationmark.triangle").foregroundStyle(SofoStyle.ink) }

            currentSceneCard

            SettingsCard {
                if model.configuration.scenes.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 23))
                            .foregroundStyle(SofoStyle.ink)
                            .frame(width: 48, height: 48)
                            .background(SofoStyle.canvas, in: SofoStyle.controlShape)
                        Text("还没有场景").font(SofoStyle.title)
                        Text("添加一个 App，为它设置专用的遥控器按键。")
                            .font(SofoStyle.prose)
                            .foregroundStyle(SofoStyle.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.configuration.scenes) { scene in
                            sceneRow(scene)
                            if scene.id != model.configuration.scenes.last?.id {
                                SofoDivider().padding(.leading, 62)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $choosingApp) {
            AppScenePicker(excluded: Set(model.configuration.scenes.map(\.id))) { id, name in
                addError = nil
                if model.addScene(id: id, name: name) {
                    editing = model.scene(id)
                } else {
                    addError = model.configurationError ?? "这个 App 已有场景。"
                }
            }
        }
        .sheet(item: $editing) { scene in
            SceneEditor(model: model, sceneID: scene.id, name: scene.name)
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

    private var currentSceneCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: SofoStyle.elementGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("根据前台 App 自动切换映射")
                            .font(SofoStyle.title)
                        Text("某个 App 在最前面时，自动套用它的映射规则。")
                            .font(SofoStyle.prose)
                            .foregroundStyle(SofoStyle.muted)
                    }
                    Spacer()
                    Toggle("根据前台 App 自动切换映射",
                           isOn: Binding(get: { model.configuration.automatic }, set: model.setAutomaticScenes))
                        .labelsHidden()
                        .toggleStyle(SofoPillSwitch())
                }
                SofoDivider()
                HStack(spacing: 8) {
                    Label("当前前台：", systemImage: "macwindow")
                        .foregroundStyle(SofoStyle.muted)
                    Text(model.frontmostApp?.localizedName ?? "—").fontWeight(.semibold)
                    Spacer()
                    Text(model.activeScene?.name ?? "默认映射")
                        .foregroundStyle(SofoStyle.muted)
                }
                .font(SofoStyle.label)
            }
            .padding(SofoStyle.cardPadding)
        }
    }

    private func sceneRow(_ scene: AppSceneMapping) -> some View {
        HStack(spacing: 12) {
            SceneAppIcon(id: scene.id)
            VStack(alignment: .leading, spacing: 3) {
                Text(scene.name).font(SofoStyle.title)
                Text(scene.id).font(SofoStyle.label).foregroundStyle(SofoStyle.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button("编辑") { editing = scene }
                .accessibilityLabel("编辑\(scene.name)的场景")
            Toggle("启用\(scene.name)的场景", isOn: Binding(get: { scene.enabled }, set: { model.setSceneEnabled($0, id: scene.id) }))
                .labelsHidden()
                .toggleStyle(SofoPillSwitch(width: 35, height: 16))
            Button { deleting = scene } label: { Image(systemName: "trash") }
                .accessibilityLabel("删除\(scene.name)的场景")
        }
        .padding(.horizontal, SofoStyle.cardPadding)
        .frame(minHeight: 60)
    }
}

private struct AppScenePicker: View {
    @Environment(\.dismiss) private var dismiss
    let excluded: Set<String>
    let onSelect: (String, String) -> Void
    @State private var invalid = false
    @State private var browsing = false

    private var applications: [NSRunningApplication] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !excluded.contains(id), app.localizedName != nil else { return false }
                return seen.insert(id).inserted
            }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("添加场景").font(SofoStyle.heading).tracking(SofoStyle.headingTracking)
            Text("选择一个正在运行的 App，或从应用程序文件夹中选择。")
                .font(SofoStyle.prose)
                .foregroundStyle(SofoStyle.muted)
            List(applications, id: \.processIdentifier) { app in
                if let id = app.bundleIdentifier, let name = app.localizedName {
                    Button {
                        select(id, name)
                    } label: {
                        HStack {
                            SceneAppIcon(id: id, size: 25)
                            Text(name)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 220)
            HStack {
                Button("浏览应用程序…") { browsing = true }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if invalid { Label("请选择一个还没有场景的 Mac App。", systemImage: "exclamationmark.triangle") }
        }
        .padding(22)
        .frame(width: 460)
        .background(SofoStyle.canvas)
        .foregroundStyle(SofoStyle.ink)
        .buttonStyle(SofoButtonStyle())
        .fileImporter(isPresented: $browsing, allowedContentTypes: [.applicationBundle]) { result in
            guard case .success(let url) = result else { return }
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, !excluded.contains(id) else {
                invalid = true
                return
            }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? FileManager.default.displayName(atPath: url.deletingPathExtension().path)
            select(id, name)
        }
    }

    private func select(_ id: String, _ name: String) {
        dismiss()
        onSelect(id, name)
    }
}

private struct SceneEditor: View {
    @ObservedObject var model: SofoModel
    let sceneID: String
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var selected: RemoteButton?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SceneAppIcon(id: sceneID)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(SofoStyle.heading).tracking(SofoStyle.headingTracking)
                    Text("这个 App 在前台时的映射").foregroundStyle(SofoStyle.muted)
                        .font(SofoStyle.prose)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(SofoButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            if let error = model.configurationError { Label(error, systemImage: "exclamationmark.triangle") }
            SofoDivider()
            HStack(alignment: .top, spacing: 20) {
                ScrollView {
                    let buttons = model.mappings(sceneID: sceneID)
                    VStack(spacing: 2) {
                        ForEach(RemoteButton.a2540Buttons) { button in
                            Button { selected = button } label: {
                                HStack {
                                    Image(systemName: button.glyph).frame(width: 17)
                                    Text(button.title)
                                    Spacer()
                                    Text(buttons.isEnabled(button) ? buttons[button]?.title ?? "未设置" : "已停用")
                                        .foregroundStyle(SofoStyle.muted).lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 29)
                                .background(selected == button ? SofoStyle.line : .clear, in: SofoStyle.controlShape)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected == button ? .isSelected : [])
                        }
                    }
                }
                .frame(width: 250)
                if let selected {
                    ButtonMappingEditor(model: model, button: selected, sceneID: sceneID,
                                        close: { self.selected = nil }, openShortcuts: { model.loadShortcuts(force: true) })
                        .id(selected)
                        .frame(width: 300)
                } else {
                    Text("选择一个按键来编辑它的映射")
                        .foregroundStyle(SofoStyle.muted)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(height: 420)
        }
        .padding(24)
        .background(SofoStyle.canvas)
        .foregroundStyle(SofoStyle.ink)
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
                Image(systemName: "app").resizable().foregroundStyle(SofoStyle.muted)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
