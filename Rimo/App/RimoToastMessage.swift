import Foundation

/// 统一的 Toast 消息定义，提供类型安全和一致的文案
enum ToastMessage {
    // 映射相关
    case mappingPaused
    case mappingResumed
    case actionAssigned(action: String, from: (button: String, trigger: String), to: (button: String, trigger: String))
    case configurationReadFailed(detail: String)
    case configurationSaveFailed(detail: String)

    // 语音相关
    case voiceReady
    case voiceFailed(detail: String)
    case voiceComponentsNeeded

    // 场景相关
    case scenePresetApplied(scene: String, preset: String)
    case sceneSwitched(scene: String)

    // 快捷指令相关
    case shortcutRunning(name: String)
    case shortcutCompleted(name: String)
    case shortcutFailed(detail: String)
    case shortcutListLoadFailed(detail: String)

    // 权限相关
    case permissionGranted(permission: String)
    case permissionDenied(permission: String)
    case accessibilityRequired

    var text: String {
        switch self {
        case .mappingPaused: return "映射已暂停"
        case .mappingResumed: return "映射已恢复"
        case .actionAssigned(_, _, let to):
            return "已改为\(to.trigger)"
        case .configurationReadFailed: return "映射配置读取失败"
        case .configurationSaveFailed: return "映射保存失败"

        case .voiceReady: return "语音已就绪"
        case .voiceFailed: return "遥控器语音未就绪"
        case .voiceComponentsNeeded: return "需要安装语音组件"

        case .scenePresetApplied: return "场景预设已应用"
        case .sceneSwitched(let scene): return "已切换到场景：\(scene)"

        case .shortcutRunning: return "正在运行快捷指令"
        case .shortcutCompleted: return "快捷指令已运行"
        case .shortcutFailed: return "快捷指令运行失败"
        case .shortcutListLoadFailed: return "快捷指令读取失败"

        case .permissionGranted(let permission): return "\(permission)权限已授予"
        case .permissionDenied(let permission): return "\(permission)权限被拒绝"
        case .accessibilityRequired: return "请开启辅助功能权限"
        }
    }

    var detail: String? {
        switch self {
        case .actionAssigned(let action, let from, let to):
            return "「\(action)」：\(from.button) · \(from.trigger) → \(to.button) · \(to.trigger)"
        case .configurationReadFailed(let detail),
             .configurationSaveFailed(let detail),
             .voiceFailed(let detail),
             .shortcutFailed(let detail),
             .shortcutListLoadFailed(let detail):
            return detail
        case .shortcutRunning(let name),
             .shortcutCompleted(let name):
            return name
        case .scenePresetApplied(let scene, let preset):
            return "「\(scene)」已应用「\(preset)��预设"
        default:
            return nil
        }
    }

    var kind: RimoToast.Kind {
        switch self {
        case .mappingResumed, .voiceReady, .shortcutCompleted, .scenePresetApplied, .permissionGranted:
            return .success
        case .configurationReadFailed, .configurationSaveFailed, .voiceFailed,
             .shortcutFailed, .shortcutListLoadFailed, .permissionDenied, .accessibilityRequired:
            return .error
        default:
            return .information
        }
    }
}

extension RimoToastCenter {
    /// 使用类型安全的消息显示 Toast
    func show(_ message: ToastMessage, duration: Duration? = nil) {
        show(message.text, kind: message.kind, detail: message.detail, duration: duration)
    }
}
