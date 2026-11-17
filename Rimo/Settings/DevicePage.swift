import SwiftUI

struct DevicePage: View {
    @ObservedObject var model: RimoModel

    var body: some View {
        SettingsScroll {
            Text("设备设置").font(RimoStyle.heading)
                .tracking(RimoStyle.headingTracking)
                .accessibilityAddTraits(.isHeader)

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Siri Remote", systemImage: "appletvremote.gen4")
                            .font(RimoStyle.title)
                        Spacer()
                        Button("重新检测") { model.retry() }
                    }
                    HStack(spacing: 6) {
                        RimoConnectionMark(connected: model.isRemoteConnected)
                        Text(model.statusTitle).font(RimoStyle.label).foregroundStyle(RimoStyle.muted)
                    }
                    Text("在 macOS 的蓝牙设置中连接 A2540。")
                        .font(RimoStyle.prose)
                        .foregroundStyle(RimoStyle.muted)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        RimoInlineLink(title: "打开蓝牙设置", destination: url)
                    }
                }
                .padding(RimoStyle.cardPadding)
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 13) {
                    Label("系统权限", systemImage: "lock.shield").font(RimoStyle.title)
                    permissionRow("输入监控", detail: "读取遥控器按键", allowed: model.canListen,
                                  request: model.requestInputAccess, pane: "Privacy_ListenEvent")
                    RimoDivider()
                    permissionRow("辅助功能", detail: "发送键盘快捷键", allowed: model.canPost,
                                  request: model.requestOutputAccess, pane: "Privacy_Accessibility")
                }
                .padding(RimoStyle.cardPadding)
            }

            SettingsCard { VoiceView(voice: model.voice).padding(RimoStyle.cardPadding) }

            SettingsCard {
                DisclosureGroup("按键诊断") {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.inputStatusTitle)
                        Text("当前监听模式会保留系统原按键动作。")
                            .foregroundStyle(RimoStyle.muted)
                        if let last = model.lastButton { Text("最近收到：\(last.title)") }
                        if case .failed(let result) = model.status {
                            Text("HID 打开失败：\(String(format: "0x%08X", UInt32(bitPattern: result)))")
                        }
                        if let diagnostic = model.diagnostic { Text(diagnostic).font(RimoStyle.caption) }
                        if let report = model.buttonReport { Text(report).font(RimoStyle.caption) }
                    }
                    .textSelection(.enabled)
                    .padding(.top, 10)
                }
                .padding(RimoStyle.cardPadding)
            }

            if let source = URL(string: "https://sketchfab.com/3d-models/apple-tv-4k-3rdgen-wifi-siri-remote-3rdgen-44ce2c6bdf2846ccbf1157b4f0aa1fa3"),
               let license = URL(string: "https://creativecommons.org/licenses/by/4.0/") {
                HStack(spacing: 5) {
                    Text("3D 模型：")
                    RimoInlineLink(title: "polyman", destination: source)
                    Text("·")
                    RimoInlineLink(title: "CC BY 4.0", destination: license)
                }
                .font(RimoStyle.caption)
                .foregroundStyle(RimoStyle.muted)
            }
        }
    }

    private func permissionRow(
        _ title: String, detail: String, allowed: Bool,
        request: @escaping () -> Void, pane: String
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).foregroundStyle(RimoStyle.muted)
            }
            Spacer()
            if allowed {
                Label("已允许", systemImage: "checkmark.circle").foregroundStyle(RimoStyle.muted)
            } else {
                Button("启用\(title)", action: request)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    RimoInlineLink(title: "系统设置", destination: url)
                        .accessibilityLabel("打开\(title)的系统设置")
                }
            }
        }
    }
}
