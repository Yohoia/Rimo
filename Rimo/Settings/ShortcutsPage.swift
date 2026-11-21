import SwiftUI

struct ShortcutsPage: View {
    @ObservedObject var model: RimoModel
    let showMapping: (RemoteButton) -> Void
    @State private var query = ""
    @State private var replacement: Replacement?
    @FocusState private var searching: Bool

    private var results: [SystemShortcut] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? model.systemShortcuts : model.systemShortcuts.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        SettingsScroll {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷指令").font(RimoStyle.heading)
                        .tracking(RimoStyle.headingTracking)
                        .accessibilityAddTraits(.isHeader)
                    Text("运行 Mac 上的快捷指令，或把它绑到遥控器按键。")
                        .font(RimoStyle.prose)
                        .foregroundStyle(RimoStyle.muted)
                }
                Spacer(minLength: 8)
                searchField
                Button {
                    model.loadShortcuts(force: true)
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.loadingShortcuts)
            }
            if let error = model.shortcutListError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(RimoStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let feedback = model.shortcutFeedback {
                Text(feedback).foregroundStyle(RimoStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            SettingsCard {
                if model.loadingShortcuts && results.isEmpty {
                    ProgressView("正在读取快捷指令…")
                        .frame(maxWidth: .infinity).padding(32)
                } else if results.isEmpty {
                    Text(model.shortcutListError != nil ? "点「刷新」重新读取。" :
                            query.isEmpty ? "在「快捷指令」App 中创建指令后，点「刷新」。" : "没有符合搜索的快捷指令。")
                        .foregroundStyle(RimoStyle.muted)
                        .frame(maxWidth: .infinity).padding(32)
                } else {
                    VStack(spacing: 0) {
                        ForEach(results) { shortcut in
                            row(shortcut)
                            if shortcut.id != results.last?.id { RimoDivider().padding(.leading, 59) }
                        }
                    }
                }
            }
        }
        .task { model.loadShortcuts() }
        .alert("替换按键映射？", isPresented: Binding(get: { replacement != nil }, set: { if !$0 { replacement = nil } })) {
            Button("取消", role: .cancel) { replacement = nil }
            Button("替换") {
                if let replacement { bind(replacement.shortcut, to: replacement.button) }
                replacement = nil
            }
        } message: {
            if let replacement {
                Text("「\(replacement.button.title)」的原映射将改为运行「\(replacement.shortcut.name)」。")
            }
        }
    }

    private var searchField: some View {
        let shape = RimoStyle.controlShape
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RimoStyle.muted)
                .accessibilityHidden(true)
            TextField("搜索快捷指令", text: $query)
                .textFieldStyle(.plain)
                .focused($searching)
                .accessibilityLabel("搜索快捷指令")
        }
        .font(RimoStyle.body)
        .padding(.horizontal, 12)
        .frame(width: 176, height: 32)
        .background(RimoStyle.surface, in: shape)
        .overlay { shape.strokeBorder(searching ? RimoStyle.ink : RimoStyle.line).allowsHitTesting(false) }
    }

    private func row(_ shortcut: SystemShortcut) -> some View {
        let bound = RemoteButton.a2540Buttons.filter {
            if case .shortcut(let mapped) = model.configuration.global[$0] { return mapped.id == shortcut.id }
            return false
        }
        return HStack(spacing: 12) {
            Image(systemName: "square.on.square")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(RimoStyle.ink)
                .frame(width: 30, height: 30)
                .background(RimoStyle.canvas, in: RimoStyle.controlShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(shortcut.name).font(RimoStyle.title).lineLimit(1)
                if !bound.isEmpty {
                    Text("遥控器：\(bound.map(\.title).joined(separator: "、"))")
                        .font(RimoStyle.label)
                        .foregroundStyle(RimoStyle.muted)
                }
            }
            Spacer()
            Menu("绑到按键") {
                ForEach(RemoteButton.a2540Buttons) { button in
                    Button {
                        if let old = model.configuration.global[button], old != .shortcut(shortcut) {
                            replacement = Replacement(shortcut: shortcut, button: button)
                        } else {
                            bind(shortcut, to: button)
                        }
                    } label: {
                        Label(button.title, systemImage: button.glyph)
                    }
                }
            }
            .accessibilityLabel("将\(shortcut.name)绑到按键")
            .fixedSize()
            let running = model.runningShortcuts.contains(shortcut.id)
            Button {
                model.runShortcut(shortcut)
            } label: {
                Label(running ? "运行中…" : "运行", systemImage: "play")
            }
            .disabled(running)
            .accessibilityLabel(running ? "正在运行\(shortcut.name)" : "运行\(shortcut.name)")
        }
        .frame(minHeight: 57)
        .padding(.horizontal, RimoStyle.cardPadding)
    }

    private func bind(_ shortcut: SystemShortcut, to button: RemoteButton) {
        model.setAction(.shortcut(shortcut), for: button)
        if model.configurationError == nil { showMapping(button) }
    }

    private struct Replacement {
        let shortcut: SystemShortcut
        let button: RemoteButton
    }
}
