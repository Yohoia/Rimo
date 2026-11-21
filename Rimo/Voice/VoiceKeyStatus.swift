import AppKit
import SwiftUI

/// Shown on the Siri key when it presses an input method's voice key. As in
/// Voxa ("press the key + supply the audio"), Rimo only presses the key; the
/// input method listens to Rimo Remote Microphone and does the recognition.
struct VoiceKeyStatus: View {
    @ObservedObject var voice: VoiceController
    @ObservedObject var helper: VoiceHelperClient
    var horizontalInset: CGFloat = 32
    @State private var working = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("遥控器麦克风", systemImage: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
            Text("按住 Siri 键时，声音会送到 Rimo Remote Microphone。请在输入法的设置里把麦克风选为它。")
                .font(RimoStyle.label)
                .foregroundStyle(RimoStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                if working || helper.deploying || voice.state == .authorizing {
                    ProgressView().controlSize(.small)
                }
                Text(message ?? statusText)
                    .font(RimoStyle.label)
                    .foregroundStyle(RimoStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if voice.state == .recording || voice.state == .draining {
                ProgressView(value: voice.level)
                    .tint(RimoStyle.assignmentAccent)
                    .accessibilityLabel("遥控器收音音量")
            }
            if !voice.installed, helper.installation == .missing {
                Button("安装语音组件…") { install() }
                    .buttonStyle(RimoButtonStyle(primary: true))
                    .disabled(working || helper.deploying)
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 14)
        .onAppear { helper.refreshStatus() }
    }

    private var statusText: String {
        if working || helper.deploying { return "正在安装语音组件…" }
        if case .unavailable(let reason) = helper.installation { return reason }
        if !voice.installed { return "语音组件未安装，需要输入一次 Mac 登录密码。" }
        if case .failed(let reason) = voice.state { return reason }
        if voice.state == .ready { return "已就绪，单次最长约 60 秒。" }
        return voice.state.title
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
