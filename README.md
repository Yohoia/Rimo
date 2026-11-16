# sofo

sofo 是一款用 Apple TV Siri Remote 控制 Mac 的 macOS 应用。你可以把遥控器按键映射为键盘快捷键或系统「快捷指令」，也可以为不同 App 设置各自的映射。首要实测机型为 **A2540**。

## 功能

- **按键映射**：点击 3D 遥控器上的按键或对应卡片，录制快捷键、绑定系统快捷指令，或停用单个按键。
- **场景**：为不同 App 设置映射，并根据前台 App 自动切换；没有专用场景时使用全局映射。
- **菜单栏与 Dock**：打开设置、查看连接状态和暂停映射。
- **遥控器收音（实验性）**：按住 Siri 侧键收音，松开后保存至本机，并可通过可选的虚拟麦克风提供给其他 App。

## 从源码构建

需要 Xcode（支持 Swift 6）和与目标架构匹配的静态 Opus 库。工程的最低部署目标是 macOS 13；实际可运行的最低版本也受链接的 Opus 库限制。

```sh
git clone https://github.com/Yohoia/sofo.git
cd sofo
brew install opus
xcodebuild -project sofo.xcodeproj -scheme sofo -configuration Debug \
  -derivedDataPath .build/xcode SOFO_OPUS_PREFIX="$(brew --prefix opus)" build
open .build/xcode/Build/Products/Debug/sofo.app
```

也可以打开 `sofo.xcodeproj`，选择 `sofo` scheme 后运行。Xcode 默认使用对应架构的标准 Homebrew 路径；其他安装位置可通过 `SOFO_OPUS_PREFIX` 指定包含 `lib/libopus.a` 的目录。

## 使用遥控器

1. 在 macOS 的「系统设置 → 蓝牙」配对 A2540，然后打开 sofo，在「设备设置」确认已连接。
2. 给 sofo 授予「输入监控」和「辅助功能」权限，用于读取按键和发送键盘事件。授权后点「重新检测」；如有系统提示，重启 sofo。
3. 在「映射」页选择按键并设置操作，再切到目标 App 试用。比如把「播放 / 暂停」映射为回车，在文本编辑器里按下遥控器按键。

目前 sofo 使用被动监听，部分按键可能仍会同时触发 macOS 原有动作。其它机型尚未验证。

### 可选：遥控器收音

普通按键映射不依赖 PacketLogger。若要开启实验性收音，请从 [Apple 蓝牙开发者资源](https://developer.apple.com/bluetooth/) 获取官方 `PacketLogger.app`，并在构建前选择一种放置方式：

- 放到项目本地的 `.local/PacketLogger.app`，或安装到 `/Applications/PacketLogger.app`。
- 在上述 `xcodebuild` 命令中追加 `SOFO_PACKETLOGGER_APP="/绝对路径/PacketLogger.app"`（放在 `build` 前后均可），或在 Xcode 中设置同名构建变量。

构建时会验证 PacketLogger 的 Apple 签名。收音还需要 Apple 的 macOS 蓝牙日志描述文件与本机管理员授权。启用后，Siri 侧键由收音功能接管；在 sofo 里停止收音或退出应用即可结束采集。录音保存于 `~/Library/Application Support/sofo/Recordings/`。虚拟麦克风需从「设备设置」单独安装；该流程仍在实验阶段。

## 项目资料

- [功能范围和已知限制](docs/product-scope.md)
- [A2540 收音诊断工具](sofo/Input/VoicePrototype/README.md) 与 [回放测试](Tests/VoiceReplay.swift)
- [界面规范](design/DESIGN.md)、[设计变量](design/tokens.json) 和 [SwiftUI 共享样式](sofo/Settings/SettingsView.swift)

第三方资源分别遵循各自许可：[Siri Remote 3D 模型（CC BY 4.0）](sofo/Resources/SiriRemote-LICENSE.txt)、[Geist（SIL OFL 1.1）](sofo/Resources/Geist/OFL-Geist.txt)和 [Opus](sofo/Resources/Opus-LICENSE.txt)。
