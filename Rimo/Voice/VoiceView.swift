import SwiftUI

struct VoiceView: View {
    @ObservedObject var voice: VoiceController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("遥控器收音", systemImage: "mic")
                    .font(RimoStyle.title)
                Spacer()
                Button(voice.enabled ? "停止收音" : "启用收音…") {
                    if voice.enabled { voice.stop() } else { voice.start() }
                }
            }
            HStack(spacing: 8) {
                if voice.state == .authorizing { ProgressView().controlSize(.small) }
                if isFailure { Image(systemName: "exclamationmark.triangle").accessibilityHidden(true) }
                Text(voice.state.title)
                    .font(RimoStyle.caption)
                    .foregroundStyle(isFailure ? RimoStyle.ink : RimoStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if voice.state == .recording {
                HStack {
                    ProgressView(value: voice.level)
                        .accessibilityLabel("遥控器收音音量")
                        .accessibilityValue("\(Int(voice.level * 100))%")
                    Text(String(format: "%.1f 秒", voice.duration))
                        .font(RimoStyle.caption)
                }
            }
            Text(voice.enabled ? "Siri 侧键已用于收音，松开后自动保存。" : "按住 Siri 侧键说话，松开结束。启用时需要管理员授权。")
                .font(RimoStyle.body).foregroundStyle(RimoStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            if voice.lastRecording != nil {
                HStack {
                    Text(String(format: "最近录音 · %.2f 秒", voice.lastDuration))
                        .font(RimoStyle.caption)
                    Spacer()
                    Button(voice.playing ? "停止播放" : "播放录音") { voice.playLastRecording() }
                    Button("在访达中显示") { voice.revealRecordings() }
                }
            }
            if let detail = voice.detail {
                Text(detail).font(RimoStyle.caption).foregroundStyle(RimoStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            MicrophoneView(microphone: voice.microphone)
        }
    }

    private var isFailure: Bool {
        if case .failed = voice.state { return true }
        return false
    }
}

private struct MicrophoneView: View {
    @ObservedObject var microphone: MicrophoneBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("系统麦克风").font(RimoStyle.title)
                Spacer()
                if microphone.installing {
                    ProgressView().controlSize(.small)
                    Text("等待安装授权…").font(RimoStyle.label)
                } else if microphone.available {
                    Label("已就绪", systemImage: "checkmark.circle").font(RimoStyle.label)
                } else if !microphone.installed {
                    Button("安装麦克风…") { microphone.install() }
                }
            }
            Text(microphone.available ? "在其他 App 中选择 Rimo Remote Microphone，启用收音后按住 Siri 键说话。" : microphone.installed ? "驱动已安装，请重新启动 Mac 后使用。" : "安装后，其他 App 可以把遥控器选作麦克风。安装需要管理员授权，完成后需重启 Mac。")
                .font(RimoStyle.body).foregroundStyle(RimoStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let message = microphone.message {
                Text(message).font(RimoStyle.caption).foregroundStyle(RimoStyle.muted)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .padding(.top, 6)
    }
}
