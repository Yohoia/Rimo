import AppKit
import SwiftUI

enum DeviceSettingsStyle {
    static let heading = Font.system(size: 14, weight: .bold)
    static let title = Font.system(size: 16, weight: .bold)
    static let body = Font.system(size: 14)
    static let text = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 251 / 255, green: 251 / 255, blue: 251 / 255, alpha: 1)
            : NSColor(srgbRed: 34 / 255, green: 36 / 255, blue: 37 / 255, alpha: 1)
    })
    static let sectionText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.8, alpha: 1)
            : NSColor(srgbRed: 34 / 255, green: 36 / 255, blue: 37 / 255, alpha: 0.4)
    })
    static let action = RimoStyle.assignmentAccent
}

struct DeviceSettingsLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(DeviceSettingsStyle.action)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .frame(minHeight: 20, alignment: .leading)
            .contentShape(Rectangle())
    }
}

enum SettingsAppearance {
    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 14)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let outline = Color(nsColor: .separatorColor)
    static let accent = Color(red: 0.13, green: 0.35, blue: 0.98)
}


struct SettingsRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder let control: () -> Control

    init(_ title: String, description: String, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(SettingsAppearance.title)
                Text(description)
                    .font(SettingsAppearance.body)
                    .foregroundStyle(SettingsAppearance.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsControl: View {
    let title: String
    var symbol = "chevron.down"

    var body: some View {
        HStack(spacing: 18) {
            Text(title)
                .lineLimit(1)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
        }
        .font(SettingsAppearance.body)
        .foregroundStyle(.primary)
        .padding(.horizontal, 13)
        .frame(minWidth: 116, minHeight: 38)
        .background(RoundedRectangle(cornerRadius: 9).strokeBorder(SettingsAppearance.outline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct DevicePage: View {
    @ObservedObject var model: RimoModel
    let openPermissionGuide: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("关于")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SettingsAppearance.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 4)

                        VStack(spacing: 18) {
                            informationRow("型号", value: A2540Input.modelName)
                            informationRow("制造商", value: model.deviceInformation?.manufacturer)
                            informationRow("设备编号", value: deviceIdentifier)
                            informationRow("蓝牙地址", value: model.remoteAddress?.uppercased())
                        }
                    }

                    VStack(alignment: .leading, spacing: 28) {
                        Text("通用")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SettingsAppearance.secondary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 4)

                        ForEach(RimoPermission.allCases) { permission in
                            permissionRow(permission)
                        }
                    }

                    VoiceKeyStatus(voice: model.voice, helper: model.voice.helper, horizontalInset: 0)
                }
                .frame(width: min(680, geometry.size.width * 0.7 - 72), alignment: .leading)
                .padding(.top, 54)
                .padding(.bottom, 56)
                .padding(.trailing, 40)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .font(SettingsAppearance.body)
            .lineSpacing(3)
            .foregroundStyle(.primary)
            .tint(SettingsAppearance.accent)
        }
    }

    private var deviceIdentifier: String? {
        guard let information = model.deviceInformation,
              let vendor = information.vendorID, let product = information.productID else { return nil }
        return String(format: "VID %04X · PID %04X", vendor, product)
    }

    @ViewBuilder private func informationRow(_ title: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text(title).font(SettingsAppearance.title)
                Spacer(minLength: 16)
                Text(value)
                    .foregroundStyle(SettingsAppearance.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(_ permission: RimoPermission) -> some View {
        SettingsRow(permission.title, description: permission.purpose) {
            Button {
                if model.isPermissionGranted(permission) { model.openPermissionSettings(permission) }
                else { model.requestPermission(permission) }
            } label: {
                SettingsControl(title: model.isPermissionGranted(permission) ? "已允许" : "授予权限",
                                symbol: model.isPermissionGranted(permission) ? "checkmark" : "arrow.up.right")
            }
            .accessibilityLabel("\(permission.title)，\(model.isPermissionGranted(permission) ? "已允许，打开系统设置" : "授予权限")")
        }
    }
}

struct PermissionOnboardingView: View {
    @ObservedObject var model: RimoModel
    var startWithDevice = false
    let close: () -> Void
    @State private var showingWelcome = true
    @State private var showingVoice = false
    @State private var permission: RimoPermission? = .accessibility
    @State private var showingHelp = false
    @State private var initialized = false
    @Environment(\.colorScheme) private var colorScheme

    private var granted: Bool { permission.map(model.isPermissionGranted) ?? false }

    var body: some View {
        Group {
            if showingWelcome {
                welcome
            } else if showingVoice {
                VoiceSetupView(voice: model.voice) {
                    model.finishPermissionOnboarding()
                    close()
                }
            } else if let permission {
                permissionPage(permission)
            } else {
                RemotePairingView(model: model, completesExistingConnection: !startWithDevice, close: {
                    if startWithDevice || model.permissionOnboardingCompleted { close() }
                    else { showingWelcome = true }
                }, connected: {
                    if model.voice.needsOnboarding { showingVoice = true }
                    else { model.finishPermissionOnboarding(); close() }
                })
            }
        }
        .background(RimoStyle.canvas)
        .foregroundStyle(RimoStyle.ink)
        .onChange(of: permission) { next in
            showingHelp = false
            if !startWithDevice { model.rememberSetupPermission(next) }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            // Upgraded installs that finished setup before voice existed see only this step.
            showingVoice = model.permissionOnboardingCompleted && !startWithDevice && model.voice.needsOnboarding
            showingWelcome = !showingVoice && !startWithDevice && (!model.setupWelcomeCompleted || model.permissionOnboardingCompleted)
            permission = startWithDevice ? nil : model.setupPermission
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var welcome: some View {
        GeometryReader { geometry in
            // MainMenu.nib uses a 1200 × 680 canvas, a 188-point welcome image,
            // title top 382, description top 430 and a 40-point primary button.
            VStack(spacing: 0) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 188, height: 188)
                    .accessibilityHidden(true)
                    .padding(.bottom, 44)
                Text("欢迎使用 Rimo")
                    .font(.system(size: 32, weight: .bold))
                    .frame(height: 40)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
                Text("将 Siri Remote 变成 Mac 的遥控器，自定义按键，轻松控制常用应用程序。")
                    .font(.system(size: 14))
                    .foregroundStyle(DeviceSettingsStyle.text)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 736, minHeight: 40)
                    .padding(.bottom, 70)
                Button("立即体验") {
                    model.beginSetup()
                    permission = .accessibility
                    model.rememberSetupPermission(.accessibility)
                    showingWelcome = false
                }
                .buttonStyle(RimoButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 40)
            .padding(.top, max(50, (geometry.size.height - 680) / 2 + 150))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func permissionPage(_ permission: RimoPermission) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: 28)
                Group {
                    if granted {
                        Image(colorScheme == .dark ? "PermissionSuccessDark" : "PermissionSuccess")
                            .resizable()
                            .scaledToFit()
                    } else {
                        PermissionSettingsIllustration(permission: permission)
                    }
                }
                // .opt-in-container-image is 63% wide and its child is 50% wide.
                .frame(width: geometry.size.width * 0.315,
                       height: geometry.size.width * 0.315 * (granted ? 0.5 : 0.61))
                .accessibilityHidden(true)
                .padding(.bottom, granted ? 18 : 36)
                Text(granted ? "已获得\(permission.title)权限！" : "授予\(permission.title)权限")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, granted ? 36 : 16)
                if !granted {
                    Text("\(permission.purpose)\(permission.instructions)")
                        .font(.system(size: 14))
                        .foregroundStyle(DeviceSettingsStyle.text)
                        .lineSpacing(5)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 785)
                    Button("需要帮助？") { showingHelp.toggle() }
                        .buttonStyle(DeviceSettingsLinkStyle())
                        .padding(.top, 8)
                    if showingHelp {
                        Text("如果列表中没有 Rimo，请先点击下方按钮。若系统提示重新打开应用，请选择“退出并重新打开”，然后继续完成授权。")
                            .font(.system(size: 14))
                            .foregroundStyle(RimoStyle.muted)
                            .lineSpacing(5)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 650)
                            .padding(.top, 12)
                    }
                }
                Button(granted ? "继续" : "打开\(permission.title)") {
                    if granted {
                        let following = RimoPermission.allCases.drop(while: { $0 != permission }).dropFirst()
                        self.permission = following.first
                    } else { model.requestPermission(permission) }
                }
                .buttonStyle(RimoButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .padding(.top, granted ? 0 : 28)
                Spacer(minLength: 28)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if !granted {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index == RimoPermission.allCases.firstIndex(of: permission) ? RimoStyle.action : RimoStyle.line)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityLabel("第 \((RimoPermission.allCases.firstIndex(of: permission) ?? 0) + 1) 项权限，共 3 项")
                    .padding(.bottom, 48)
                }
            }
        }
    }
}

/// The final setup step. Like Voxa and RemotePilot, every root-side voice
/// component is installed with a single administrator prompt, after which voice
/// runs automatically whenever the remote is connected.
private struct VoiceSetupView: View {
    @ObservedObject var voice: VoiceController
    let finish: () -> Void
    @State private var installing = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(RimoStyle.action)
                .accessibilityHidden(true)
                .padding(.bottom, 36)
            Text("启用遥控器语音")
                .font(.system(size: 32, weight: .bold))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 16)
            Text("把 Siri 键映射成输入法的语音快捷键（如 Typeless 的 Fn、豆包的 Option），按住 Siri 键说话，声音会通过 Rimo Remote Microphone 交给输入法。安装需要输入一次 Mac 登录密码，之后自动运行。")
                .font(.system(size: 14))
                .foregroundStyle(DeviceSettingsStyle.text)
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640)
            if let error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(RimoStyle.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
                    .padding(.top, 12)
            }
            Button(installing ? "正在安装…" : "启用") {
                installing = true
                error = nil
                Task {
                    defer { installing = false }
                    do { try await voice.install(); finish() }
                    catch { self.error = error.localizedDescription }
                }
            }
            .buttonStyle(RimoButtonStyle(primary: true))
            .keyboardShortcut(.defaultAction)
            .disabled(installing)
            .padding(.top, 28)
            Button("暂不启用") {
                voice.declineSetup(); finish()
            }
            .buttonStyle(DeviceSettingsLinkStyle())
            .disabled(installing)
            .padding(.top, 16)
            Spacer(minLength: 28)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Native reconstruction of Options+ Ventura permission artwork. The reference
/// bindings are _0xb251b6 (accessibility), _0x47d154 (input), _0x55aec1 (Bluetooth).
private struct PermissionSettingsIllustration: View {
    let permission: RimoPermission

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 400
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(RimoStyle.action).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.bottom, 2)
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10))
                        Spacer()
                    }
                    .foregroundStyle(RimoStyle.quiet)
                    .padding(6)
                    .background(RimoStyle.actionConfigurationFill, in: RimoStyle.controlShape)
                    ForEach(["person.crop.circle.fill", "shield.fill", "chart.bar.fill", "accessibility"], id: \.self) { icon in
                        HStack(spacing: 10) {
                            Image(systemName: icon).font(.system(size: 16)).frame(width: 18)
                            Capsule().frame(height: 4)
                        }
                        .foregroundStyle(RimoStyle.quiet.opacity(0.55))
                    }
                    Label("隐私与安全性", systemImage: "hand.raised.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0, green: 0.63, blue: 0.95), in: RimoStyle.controlShape)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(width: 164)
                .background(RimoStyle.surface)
                VStack(alignment: .leading, spacing: 12) {
                    Label(permission.title, systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    RimoDivider()
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().frame(width: 96, height: 5)
                        Capsule().frame(width: 64, height: 5)
                    }
                    .foregroundStyle(RimoStyle.quiet.opacity(0.6))
                    .padding(.vertical, 2)
                    VStack(spacing: 0) {
                        previewRow(highlighted: false)
                        RimoDivider()
                        previewRow(highlighted: true)
                        RimoDivider()
                        previewRow(highlighted: false)
                    }
                    .background(RimoStyle.surface)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RimoStyle.actionSidebarHeader)
            }
            .frame(width: 400, height: 244)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(RimoStyle.line) }
            .scaleEffect(scale, anchor: .topLeading)
        }
    }

    private func previewRow(highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            if highlighted {
                Image("RimoBrandIcon").resizable().frame(width: 20, height: 20)
                Text("Rimo").font(.system(size: 12, weight: .semibold))
            } else {
                RoundedRectangle(cornerRadius: 3).fill(RimoStyle.line).frame(width: 20, height: 20)
                Capsule().fill(RimoStyle.line).frame(width: 52, height: 4)
            }
            Spacer(minLength: 4)
            Capsule()
                .fill(RimoStyle.action)
                .frame(width: 21, height: 11)
                .overlay(alignment: .trailing) {
                    Circle().fill(.white).padding(2).frame(width: 11, height: 11)
                }
        }
        .padding(.horizontal, 8)
        .frame(height: 43)
    }
}

private struct RemotePairingView: View {
    @ObservedObject var model: RimoModel
    let completesExistingConnection: Bool
    let close: () -> Void
    let connected: () -> Void
    @State private var openedBluetoothSettings = false
    @State private var finished = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    Text("选择连接类型")
                        .font(.system(size: 24, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 45)
                    Spacer()
                    Text("要配对您的遥控器，请通过蓝牙连接")
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(32, geometry.size.height * 0.065))
                }
                BluetoothConnectionRow {
                    openedBluetoothSettings = true
                }
                    .frame(width: geometry.size.width * 0.4)
                VStack {
                    HStack {
                        Button(action: close) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("返回设备首页")
                        .keyboardShortcut(.cancelAction)
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.top, 30)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RimoStyle.canvas)
        .foregroundStyle(DeviceSettingsStyle.text)
        .onAppear {
            if completesExistingConnection { finishIfConnected() }
        }
        .onChange(of: model.isRemoteConnected) { connected in
            if connected { finishIfConnected() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if openedBluetoothSettings { finishIfConnected() }
        }
    }

    private func finishIfConnected() {
        guard model.isRemoteConnected, !finished else { return }
        finished = true
        connected()
    }
}

private struct BluetoothConnectionRow: View {
    let openSettings: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button {
            if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                openSettings()
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 16) {
                Image("BluetoothMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 15, height: 24)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 30)
                    .background(Color(red: 0, green: 0.48, blue: 1), in: RoundedRectangle(cornerRadius: 12))
                    .frame(width: 36)
                Text("蓝牙")
                    .font(.system(size: 16))
                    .foregroundStyle(DeviceSettingsStyle.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(hovering ? DeviceSettingsStyle.action : DeviceSettingsStyle.text)
            }
            .padding(.horizontal, 24)
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .background(hovering ? RimoStyle.action.opacity(0.04) : RimoStyle.surface,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? DeviceSettingsStyle.action : RimoStyle.line,
                                  lineWidth: focused ? 2 : 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, x: 2, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovering = $0 }
        .accessibilityLabel("蓝牙，打开系统蓝牙设置")
    }
}
