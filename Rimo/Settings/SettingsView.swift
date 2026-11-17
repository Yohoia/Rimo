import AppKit
import SwiftUI

enum RimoStyle {
    // Main app palette; see docs/device-interface.md.
    static let canvas = adaptive(light: 0xFBFBFB, dark: 0x171717)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x202020)
    static let line = adaptive(light: 0xE1E2E3, dark: 0x363636)
    static let ink = adaptive(light: 0x171717, dark: 0xFBFBFB)
    static let muted = adaptive(light: 0x6F7171, dark: 0xA8A8A8)
    static let secondaryText = adaptive(light: 0x434546, dark: 0xC9C9C9)
    static let quiet = adaptive(light: 0xC9C9C9, dark: 0x606060)
    static let action = Color(red: 129.0 / 255, green: 78.0 / 255, blue: 250.0 / 255)
    static let actionPressed = Color(red: 110.0 / 255, green: 61.0 / 255, blue: 224.0 / 255)
    static let actionLabel = Color.white
    static let assignmentAccent = adaptive(light: 0x814EFA, dark: 0x00EAD0)
    static let assignmentInk = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let assignmentBorder = adaptive(light: 0x6039B2, dark: 0x03BAA5)
    static let actionSidebarHeader = adaptive(light: 0xEBEBEB, dark: 0x292929)
    static let actionSidebarDivider = adaptive(light: 0xEEEEEE, dark: 0x363636)
    static let actionRadio = adaptive(light: 0xE1E2E3, dark: 0x555555)
    static let actionSearchPlaceholder = adaptive(light: 0xA2A3A5, dark: 0xA8A8A8)
    static let success = adaptive(light: 0x297A3A, dark: 0x79CE88)

    static let cardRadius: CGFloat = 4
    static let navRadius: CGFloat = 2
    static let cardPadding: CGFloat = 16
    static let elementGap: CGFloat = 12
    static let cardRing = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.16 : 0.08)
    })

    static let body = Font.system(size: 14)
    static let title = Font.system(size: 14, weight: .bold)
    static let label = Font.system(size: 13)
    static let caption = Font.system(size: 13)
    static let heading = Font.custom("Geist-Regular", fixedSize: 30)
    static let headingTracking: CGFloat = -1.5
    static let prose = Font.custom("Geist-Regular", fixedSize: 16)
    static let modelHeading = Font.custom("GeistMono-Regular", fixedSize: 14)
    static let brand = Font.custom("Geist-Medium", fixedSize: 49)
    static let stateDuration: TimeInterval = 0.18

    static let controlShape = RoundedRectangle(cornerRadius: cardRadius)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        })
    }

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

struct RimoConnectionMark: View {
    let connected: Bool
    var body: some View {
        Group {
            if connected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RimoStyle.success)
            } else {
                Circle().strokeBorder(RimoStyle.muted).frame(width: 6, height: 6)
            }
        }
        .frame(width: 10, height: 12)
        .accessibilityHidden(true)
    }
}

struct RimoDivider: View {
    var body: some View {
        Rectangle()
            .fill(RimoStyle.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct RimoButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, primary: primary)
    }

    private struct Surface: View {
        let configuration: ButtonStyle.Configuration
        let primary: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let active = enabled && (hovering || configuration.isPressed)
            let shape = RimoStyle.controlShape
            configuration.label
                .font(.system(size: 14, weight: primary ? .bold : .regular))
                .foregroundStyle(enabled ? (primary ? RimoStyle.actionLabel : RimoStyle.secondaryText) : RimoStyle.muted)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(enabled ? (primary ? (active ? RimoStyle.actionPressed : RimoStyle.action) : active ? RimoStyle.line : .clear)
                            : RimoStyle.canvas, in: shape)
                .overlay {
                    shape.strokeBorder(primary && enabled ? .clear : enabled ? RimoStyle.line : RimoStyle.quiet)
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(focused ? RimoStyle.action : .clear, lineWidth: 2)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: RimoStyle.stateDuration), value: active)
        }
    }
}

struct RimoSettingsView: View {
    @ObservedObject var model: RimoModel
    @State private var tab = SettingsTab.home
    @State private var selected: RemoteButton?
    @State private var deviceDetail = false
    @State private var addApp = false
    @State private var warmScene = false
    @State private var sceneReady = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showing3D: Bool { tab == .mapping && sceneReady }
    private var editingButton: Bool { tab == .mapping && selected != nil }

    var body: some View {
        GeometryReader { geometry in
            let width = ActionSidebarLayout.width(in: geometry.size.width)
            content(sidebarWidth: width)
                .overlay(alignment: .trailing) {
                    ZStack(alignment: .trailing) {
                        if showing3D, let selected {
                            actionSidebar(for: selected, width: width)
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .animation(reduceMotion ? nil : sidebarAnimation, value: showing3D && editingButton)
                }
                .clipped()
        }
        .sheet(isPresented: $addApp) {
            AppScenePicker(excluded: Set(model.configuration.scenes.map(\.id))) { app in
                _ = model.addScene(id: app.id, name: app.name)
                tab = .scenes
            }
        }
        .background(RimoStyle.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .tint(RimoStyle.action)
        .foregroundStyle(RimoStyle.ink)
        .font(RimoStyle.body)
        .onChange(of: tab) { next in
            if next != .home && next != .mapping { warmScene = false; sceneReady = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var sidebarAnimation: Animation {
        editingButton ? .easeOut(duration: 0.25).delay(0.18) : .easeInOut(duration: 0.24)
    }

    private func actionSidebar(for button: RemoteButton, width: CGFloat) -> some View {
        ButtonMappingEditor(model: model, button: button, inSidebar: true,
                            close: { selected = nil }, openShortcuts: {
                                selected = nil
                                tab = .shortcuts
                            })
            .id(button)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background { RimoStyle.surface.shadow(color: .black.opacity(0.08), radius: 18, x: -6) }
    }

    private func content(sidebarWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(sidebarWidth: sidebarWidth)
            if let error = model.configurationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(RimoStyle.body)
                    .foregroundStyle(RimoStyle.ink)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Group {
                switch tab {
                case .home, .mapping:
                    ZStack {
                        if warmScene || tab == .mapping {
                            MappingView(model: model, selected: $selected,
                                        presentationActive: showing3D, onReady: { sceneReady = true })
                                // A near-transparent view renders its first frame while the still covers it.
                                .opacity(showing3D ? 1 : 0.001)
                                .allowsHitTesting(showing3D)
                                .accessibilityHidden(!showing3D)
                        }
                        DeviceHomeView(model: model) {
                            selected = nil
                            deviceDetail = true
                            tab = .mapping
                        }
                        .opacity(showing3D ? 0 : 1)
                        .allowsHitTesting(tab == .home)
                        .accessibilityHidden(showing3D)
                    }
                    .task { warmScene = true }
                case .scenes:
                    ScenesPage(model: model, openDeviceSettings: { tab = .device })
                        .padding(.leading, deviceDetail ? 170 : 0)
                case .shortcuts:
                    ShortcutsPage(model: model) { button in
                        selected = button
                        deviceDetail = true
                        tab = .mapping
                    }
                    .padding(.leading, deviceDetail ? 170 : 0)
                case .device:
                    DevicePage(model: model)
                        .padding(.leading, deviceDetail ? 170 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                if deviceDetail && (tab != .mapping || showing3D) {
                    deviceSidebar
                }
            }
        }
    }

    @ViewBuilder private func header(sidebarWidth: CGFloat) -> some View {
        if deviceDetail {
            deviceHeader(sidebarWidth: sidebarWidth)
        } else {
            homeHeader
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                selected = nil
                tab = .home
            } label: {
                Text("欢迎回来")
                    .font(RimoStyle.heading)
                    .tracking(RimoStyle.headingTracking)
                    .foregroundStyle(RimoStyle.ink)
                    .fixedSize()
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("欢迎回来，返回首页")
            .help("返回遥控器首页")

            Spacer(minLength: 24)

            HStack(spacing: 12) {
                if tab != .home {
                    toolbarButton("遥控器首页", icon: "appletvremote.gen4", selected: false) {
                        selected = nil
                        tab = .home
                    }
                }
                toolbarButton("场景", icon: "square.3.layers.3d", selected: tab == .scenes) {
                    tab = tab == .scenes ? .home : .scenes
                }
                toolbarButton("快捷指令", icon: "command", selected: tab == .shortcuts) {
                    tab = tab == .shortcuts ? .home : .shortcuts
                }

                Rectangle().fill(RimoStyle.line).frame(width: 1, height: 24).padding(.horizontal, 8)
                    .accessibilityHidden(true)

                toolbarButton(model.paused ? "恢复映射" : "暂停映射",
                              icon: model.paused ? "play.circle" : "pause.circle", selected: model.paused) {
                    model.togglePaused()
                }
                toolbarButton("设备设置", icon: "gearshape", selected: tab == .device) {
                    tab = tab == .device ? .home : .device
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("功能菜单")
        }
        .padding(.leading, 52)
        .padding(.trailing, 32)
        .frame(height: 100)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private func deviceHeader(sidebarWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Button {
                if !editingButton {
                    deviceDetail = false
                    tab = .home
                }
                selected = nil
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 36, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editingButton ? "返回按键列表" : "返回首页")
            .keyboardShortcut(editingButton ? .cancelAction : nil)
            if !editingButton {
                Text("Apple TV Siri Remote")
                    .font(.system(size: 30, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 24)
            Button { selected = nil; tab = .mapping } label: {
                Image(systemName: "circle.grid.2x2")
                    .font(.system(size: 21))
                    .frame(width: 40, height: 42)
                    .foregroundStyle(RimoStyle.action)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(RimoStyle.action).frame(width: 32, height: 2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全局映射")
            .help("全局映射")
            Rectangle().fill(RimoStyle.line).frame(width: 1, height: 24).padding(.horizontal, 16)
                .accessibilityHidden(true)
            Button { addApp = true } label: {
                Label("添加应用程序", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 44)
        .padding(.trailing, editingButton ? sidebarWidth + max(48, sidebarWidth * 0.19) : 48)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.29), value: editingButton)
        .frame(height: 76)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private var deviceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                deviceSection("按钮", icon: "switch.2", destination: .mapping)
                deviceSection("场景", icon: "square.3.layers.3d", destination: .scenes)
                deviceSection("快捷指令", icon: "command", destination: .shortcuts)
                deviceSection("设置", icon: "slider.horizontal.3", destination: .device)
            }
            Spacer()
            DeviceBatteryBadge(model: model)
                .padding(.bottom, 34)
        }
        .padding(.leading, 46)
        .frame(width: 166, alignment: .leading)
        .offset(x: editingButton ? -176 : 0)
        .opacity(editingButton ? 0 : 1)
        .allowsHitTesting(!editingButton)
        .accessibilityHidden(editingButton)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: editingButton)
    }

    private func deviceSection(_ title: String, icon: String, destination: SettingsTab) -> some View {
        Button { selected = nil; tab = destination } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .medium))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .foregroundStyle(tab == destination ? .white : RimoStyle.ink)
                .background(tab == destination ? RimoStyle.action : .clear, in: RimoStyle.controlShape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == destination ? .isSelected : [])
    }

    private func toolbarButton(_ title: String, icon: String, selected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(HomeToolbarStyle(selected: selected))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title)
    }

    private enum SettingsTab: CaseIterable, Identifiable {
        case home, mapping, scenes, shortcuts, device
        var id: Self { self }
        var title: String {
            switch self {
            case .home: "首页"
            case .mapping: "映射"
            case .scenes: "场景"
            case .shortcuts: "快捷指令"
            case .device: "设备设置"
            }
        }
        var icon: String {
            switch self {
            case .home: "house"
            case .mapping: "square.grid.2x2"
            case .scenes: "square.3.layers.3d"
            case .shortcuts: "command"
            case .device: "gearshape"
            }
        }
    }
}

/// The home screen displays the bundled still while SceneKit prepares the detail view.
private struct DeviceHomeView: View {
    @ObservedObject var model: RimoModel
    let openDevice: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let imageHeight = RemotePresentation.height(in: geometry.size.height)
            VStack(spacing: 20) {
                Button(action: openDevice) {
                    Image("RemotePreview")
                        .resizable()
                        .scaledToFit()
                        .frame(height: imageHeight)
                        .opacity(model.isRemoteConnected ? 1 : 0.40)
                        .shadow(color: .black.opacity(model.isRemoteConnected ? 0.20 : 0.08),
                                radius: 13, x: 20, y: 15)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .offset(y: hovered || focused ? -12 : 0)
                }
                .buttonStyle(.plain)
                .focused($focused)
                .disabled(!model.isRemoteConnected)
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: hovered || focused)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(focused ? RimoStyle.action : .clear, lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("Apple TV Siri Remote A2540")
                .accessibilityHint(model.isRemoteConnected ? "打开 3D 遥控器与按键映射" : "请先连接遥控器")
                .help(model.isRemoteConnected ? "A2540 · 点击自定义按键" : "A2540 · 未连接")

                DeviceBatteryBadge(model: model)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -min(40, geometry.size.height * 0.07))
        }
    }
}

private struct DeviceBatteryBadge: View {
    @ObservedObject var model: RimoModel

    private var batteryColor: Color {
        guard model.isRemoteConnected, let percent = model.batteryPercent else { return RimoStyle.muted }
        return percent <= 10 ? Color(red: 244.0 / 255, green: 61.0 / 255, blue: 61.0 / 255)
            : percent <= 20 ? Color(red: 255.0 / 255, green: 164.0 / 255, blue: 20.0 / 255)
            : Color(red: 121.0 / 255, green: 224.0 / 255, blue: 83.0 / 255)
    }

    private var batterySymbol: String {
        guard let percent = model.batteryPercent else { return "battery.0percent" }
        return percent <= 10 ? "battery.0percent" : percent <= 35 ? "battery.25percent"
            : percent <= 60 ? "battery.50percent" : percent <= 85 ? "battery.75percent" : "battery.100percent"
    }

    var body: some View {
                HStack(spacing: 9) {
                    HStack(spacing: 6) {
                        Text(model.isRemoteConnected ? model.batteryPercent.map { "\($0)%" } ?? "电量未知" : "未连接")
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                        Image(systemName: batterySymbol)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(batteryColor)
                    Image("BluetoothMark")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 11, height: 16)
                        .foregroundStyle(model.isRemoteConnected ? RimoStyle.ink : RimoStyle.muted)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(RimoStyle.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(RimoStyle.line.opacity(0.65)) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.isRemoteConnected
                    ? "蓝牙已连接，" + (model.batteryPercent.map { "电量 \($0)%" } ?? "暂未读取到电量") : "遥控器未连接")
                .help(model.isRemoteConnected && model.batteryPercent == nil ? "暂未读取到电量，等待系统更新" : model.statusTitle)
    }
}

private struct HomeToolbarStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected)
    }

    private struct Surface: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        @State private var hovered = false
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(selected ? RimoStyle.action : RimoStyle.ink)
                .background(hovered || configuration.isPressed ? RimoStyle.line.opacity(0.55) : .clear,
                            in: RimoStyle.controlShape)
                .overlay {
                    RimoStyle.controlShape.strokeBorder(focused ? RimoStyle.action : .clear, lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        }
    }
}

struct RimoPillSwitch: ToggleStyle {
    var width: CGFloat = 48
    var height: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? RimoStyle.ink : RimoStyle.line)
                .overlay {
                    Capsule().strokeBorder(configuration.isOn ? .clear : RimoStyle.muted)
                }
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? RimoStyle.canvas : RimoStyle.surface)
                        .frame(width: width * 0.58, height: height - 5)
                        .padding(.horizontal, 3)
                }
                .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

struct RimoInlineLink: View {
    let title: LocalizedStringKey
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Text(title).underline().foregroundStyle(RimoStyle.ink)
        }
        .buttonStyle(.link)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(RimoStyle.surface, in: RimoStyle.controlShape)
            .modifier(RimoCardRings())
    }
}

struct RimoCardRings: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            RimoStyle.controlShape.strokeBorder(RimoStyle.cardRing).allowsHitTesting(false)
        }
        .background {
            RoundedRectangle(cornerRadius: RimoStyle.cardRadius + 1)
                .strokeBorder(RimoStyle.canvas)
                .padding(-1)
                .allowsHitTesting(false)
        }
    }
}

struct SettingsScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RimoStyle.elementGap) { content }
                .frame(maxWidth: 940, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(RimoButtonStyle())
    }
}
