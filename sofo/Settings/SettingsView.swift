import AppKit
import SwiftUI

enum SofoStyle {
    // Light tokens agree across design/tokens.json, variables.css and theme.css.
    static let canvas = adaptive(light: 0xFAFAFA, dark: 0x171717)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x202020)
    static let line = adaptive(light: 0xEBEBEB, dark: 0x363636)
    static let ink = adaptive(light: 0x171717, dark: 0xFAFAFA)
    static let muted = adaptive(light: 0x666666, dark: 0xA8A8A8)
    static let secondaryText = adaptive(light: 0x4D4D4D, dark: 0xC9C9C9)
    static let quiet = adaptive(light: 0xC9C9C9, dark: 0x606060)
    static let action = ink
    static let actionPressed = secondaryText
    static let actionLabel = adaptive(light: 0xFFFFFF, dark: 0x171717)
    static let success = adaptive(light: 0x297A3A, dark: 0x79CE88)

    static let cardRadius: CGFloat = 6
    static let navRadius: CGFloat = 2
    static let cardPadding: CGFloat = 16
    static let elementGap: CGFloat = 12
    static let cardRing = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.16 : 0.08)
    })

    static let body = Font.custom("Geist-Regular", fixedSize: 14)
    static let title = Font.custom("Geist-Medium", fixedSize: 14)
    static let label = Font.custom("GeistMono-Regular", fixedSize: 12)
    static let caption = Font.custom("GeistMono-Regular", fixedSize: 13)
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

struct SofoConnectionMark: View {
    let connected: Bool
    var body: some View {
        Group {
            if connected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SofoStyle.success)
            } else {
                Circle().strokeBorder(SofoStyle.muted).frame(width: 6, height: 6)
            }
        }
        .frame(width: 10, height: 12)
        .accessibilityHidden(true)
    }
}

struct SofoDivider: View {
    var body: some View {
        Rectangle()
            .fill(SofoStyle.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct SofoButtonStyle: ButtonStyle {
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
            let shape = SofoStyle.controlShape
            configuration.label
                .font(SofoStyle.body)
                .foregroundStyle(enabled ? (primary ? SofoStyle.actionLabel : SofoStyle.secondaryText) : SofoStyle.muted)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(enabled ? (primary ? (active ? SofoStyle.actionPressed : SofoStyle.action) : active ? SofoStyle.line : .clear)
                            : SofoStyle.canvas, in: shape)
                .overlay {
                    shape.strokeBorder(primary && enabled ? .clear : enabled ? SofoStyle.line : SofoStyle.quiet)
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(focused ? SofoStyle.ink : .clear, lineWidth: 2)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: SofoStyle.stateDuration), value: active)
        }
    }
}

struct SofoSettingsView: View {
    @ObservedObject var model: SofoModel
    @State private var tab = SettingsTab.mapping
    @State private var selected: RemoteButton?

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = model.configurationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SofoStyle.body)
                    .foregroundStyle(SofoStyle.ink)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Group {
                switch tab {
                case .mapping:
                    MappingView(model: model, selected: $selected, openShortcuts: { tab = .shortcuts })
                case .scenes:
                    ScenesPage(model: model)
                case .shortcuts:
                    ShortcutsPage(model: model) { button in
                        selected = button
                        tab = .mapping
                    }
                case .device:
                    DevicePage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SofoStyle.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .tint(SofoStyle.ink)
        .foregroundStyle(SofoStyle.ink)
        .font(SofoStyle.body)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                HStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                        .accessibilityHidden(true)
                    Text(verbatim: "sofo")
                        .font(SofoStyle.brand)
                        .tracking(-2.45)
                        .fixedSize()
                }
                .foregroundStyle(SofoStyle.ink)
                .frame(height: 54)

                Spacer()
                if tab == .mapping {
                    HStack(spacing: 9) {
                        Text(model.paused ? "映射已暂停" : "启用映射")
                            .font(SofoStyle.label)
                            .tracking(0.85)
                            .foregroundStyle(SofoStyle.muted)
                            .accessibilityHidden(true)
                        Toggle("启用映射", isOn: enabled)
                            .labelsHidden()
                            .toggleStyle(SofoPillSwitch(width: 44, height: 20))
                    }
                }
            }
            .padding(.horizontal, 35)
            navigation
        }
        .frame(height: 54)
        .offset(y: 8)
        .padding(.top, 41)
    }

    private var navigation: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { item in
                Button { tab = item } label: { Label(item.title, systemImage: item.icon) }
                    .buttonStyle(SofoNavigationStyle(selected: tab == item))
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置导航")
    }

    private var enabled: Binding<Bool> {
        Binding(get: { !model.paused }, set: { if $0 == model.paused { model.togglePaused() } })
    }

    private enum SettingsTab: CaseIterable, Identifiable {
        case mapping, scenes, shortcuts, device
        var id: Self { self }
        var title: String {
            switch self {
            case .mapping: "映射"
            case .scenes: "场景"
            case .shortcuts: "快捷指令"
            case .device: "设备设置"
            }
        }
        var icon: String {
            switch self {
            case .mapping: "square.grid.2x2"
            case .scenes: "square.3.layers.3d"
            case .shortcuts: "command"
            case .device: "gearshape"
            }
        }
    }
}

private struct SofoNavigationStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Item(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }

    private struct Item: View {
        let label: ButtonStyle.Configuration.Label
        let selected: Bool
        let pressed: Bool
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isFocused) private var focused

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: SofoStyle.navRadius)
            label.font(selected ? SofoStyle.title : SofoStyle.body)
                .foregroundStyle(selected || hovered || pressed ? SofoStyle.ink : SofoStyle.muted)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(selected ? SofoStyle.line : hovered || pressed ? SofoStyle.surface : .clear, in: shape)
                .overlay { shape.strokeBorder(focused ? SofoStyle.ink : .clear, lineWidth: 2).allowsHitTesting(false) }
                .contentShape(shape)
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: SofoStyle.stateDuration), value: hovered)
        }
    }
}

struct SofoPillSwitch: ToggleStyle {
    var width: CGFloat = 48
    var height: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? SofoStyle.ink : SofoStyle.line)
                .overlay {
                    Capsule().strokeBorder(configuration.isOn ? .clear : SofoStyle.muted)
                }
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? SofoStyle.canvas : SofoStyle.surface)
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

struct SofoInlineLink: View {
    let title: LocalizedStringKey
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Text(title).underline().foregroundStyle(SofoStyle.ink)
        }
        .buttonStyle(.link)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(SofoStyle.surface, in: SofoStyle.controlShape)
            .modifier(SofoCardRings())
    }
}

struct SofoCardRings: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            SofoStyle.controlShape.strokeBorder(SofoStyle.cardRing).allowsHitTesting(false)
        }
        .background {
            RoundedRectangle(cornerRadius: SofoStyle.cardRadius + 1)
                .strokeBorder(SofoStyle.canvas)
                .padding(-1)
                .allowsHitTesting(false)
        }
    }
}

struct SettingsScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SofoStyle.elementGap) { content }
                .frame(maxWidth: 940, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SofoButtonStyle())
    }
}
