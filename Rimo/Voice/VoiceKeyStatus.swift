import AppKit
import SwiftUI

/// Component installation status alongside the device's permission settings.
struct VoiceKeyStatus: View {
    @ObservedObject var voice: VoiceController
    @ObservedObject var helper: VoiceHelperClient
    @State private var working = false
    @State private var message: String?

    var body: some View {
        SettingsRow("遥控器麦克风", description: message ?? description) {
            if helper.installation == .installed, !busy {
                SettingsControl(title: "已就绪", symbol: "checkmark")
                    .accessibilityLabel("遥控器麦克风，语音组件已就绪")
            } else {
                Button(action: install) {
                    SettingsControl(title: statusTitle, symbol: "arrow.down", isLoading: busy)
                }
                .disabled(busy || unavailable)
                .accessibilityLabel("遥控器麦克风，\(statusTitle)，\(helper.installation == .outdated ? "更新" : "安装")语音组件")
            }
        }
        .onAppear { helper.refreshStatus() }
    }

    private var busy: Bool { working || helper.deploying }

    private var unavailable: Bool {
        if case .unavailable = helper.installation { return true }
        return false
    }

    private var statusTitle: String {
        if busy { return "安装中…" }
        return helper.installation == .outdated ? "待更新" : "待安装"
    }

    private var description: String {
        if busy { return "正在安装语音组件，请完成系统授权。" }
        if case .unavailable(let reason) = helper.installation { return reason }
        if helper.installation == .missing { return "需要安装语音组件，安装时需输入一次 Mac 登录密码。" }
        if helper.installation == .outdated { return "需要更新语音组件，更新时需输入一次 Mac 登录密码。" }
        return "按住 Siri 键说话，并在输入法中选择 Rimo Remote Microphone。"
    }

    private func install() {
        working = true
        message = nil
        Task { @MainActor in
            defer { working = false }
            do { try await voice.install() }
            catch { message = error.localizedDescription }
        }
    }
}
