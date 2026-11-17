# Rimo

Rimo 是一款用 Apple TV Siri Remote 控制 Mac 的 macOS 应用。你可以为遥控器按键分配快捷键、媒体控制、鼠标操作和其他动作，也可以按 App 使用不同的映射。首要实测机型为 **A2540**。

## 功能

- **首页**：左上角品牌返回首页，右上角进入场景、快捷指令、暂停映射和设备设置。中央展示遥控器静态图片，下方显示电量和蓝牙连接信息；点击设备进入可旋转的 3D 映射页。未连接时设备灰显并禁用交互。电量优先读取 macOS 配件电源信息，HID 作为回退；暂未读取到数据时显示「电量未知」。
- **按键映射**：浏览时遥控器轻轻摇摆，也可拖动旋转。点击模型上任意按键，视图会放大按键区域，用轮廓和短标签标出选中的键，并打开可搜索、可折叠分组的动作侧栏。可以为同一个按键的单击、双击和长按分别配置键盘快捷键、鼠标点击、四向滚动、媒体控制、系统操作、打开 App、输入文本或系统快捷指令。快捷键支持 Fn、左右修饰键及按住至松开；每种触发可以单独停用。实体按键按下时，模型会亮起对应按键。
- **场景**：为不同 App 设置映射。开启自动切换后根据前台 App 选择已启用的场景；没有匹配时使用全局映射。
- **场景预设**：内置演示翻页、长文阅读和网页视频。在「场景 → 场景预设」选好 App 并确认按键后应用。新场景中未列出的按键跟随全局映射；已有场景仅更新预设列出的按键。
- **菜单栏与 Dock**：打开设置、查看连接状态和暂停映射。
- **遥控器收音（实验性）**：按住 Siri 侧键收音，松开后保存至本机，并可通过可选的虚拟麦克风提供给其他 App。

## 从源码构建

需要 Xcode（支持 Swift 6）和与目标架构匹配的静态 Opus 库。工程的最低部署目标是 macOS 13；实际可运行的最低版本也受链接的 Opus 库限制。

```sh
git clone https://github.com/Yohoia/Rimo.git
cd Rimo
brew install opus
xcodebuild -project Rimo.xcodeproj -scheme Rimo -configuration Debug \
  -derivedDataPath .build/xcode RIMO_OPUS_PREFIX="$(brew --prefix opus)" build
open .build/xcode/Build/Products/Debug/Rimo.app
```

也可以打开 `Rimo.xcodeproj`，选择 `Rimo` scheme 后运行。Xcode 默认使用对应架构的标准 Homebrew 路径；其他安装位置可通过 `RIMO_OPUS_PREFIX` 指定包含 `lib/libopus.a` 的目录。

## 使用遥控器

1. 在 macOS 的「系统设置 → 蓝牙」配对 A2540，然后打开 Rimo，在「设备设置」确认已连接。
2. 给 Rimo 授予「输入监控」和「辅助功能」权限，用于读取按键和发送键盘事件。授权后点「重新检测」；如有系统提示，重启 Rimo。
3. 回到首页点击遥控器，再点 3D 模型上要配置的键。在右侧「动作」侧栏的标题栏选择单击、双击或长按，可搜索动作或展开分组。按 Esc 或点左上角返回箭头收起侧栏。
4. 例如，把「播放 / 暂停」的单击设为「快捷键 → 回车」，再切到文本编辑器试用。Rimo 设置窗口在前台时，实体按键只用于预览和诊断，不会执行映射。

如需为某个 App 单独配置，用设备详情右上角的「添加应用程序」创建场景，再在「场景」页编辑并开启自动切换。目前 Rimo 使用被动监听，部分按键可能仍会同时触发 macOS 原有动作。其他机型尚未验证。

### 可选：遥控器收音

普通按键映射不依赖 PacketLogger。若要开启实验性收音，请从 [Apple 蓝牙开发者资源](https://developer.apple.com/bluetooth/) 获取官方 `PacketLogger.app`，并在构建前选择一种放置方式：

- 放到项目本地的 `.local/PacketLogger.app`，或安装到 `/Applications/PacketLogger.app`。
- 在上述 `xcodebuild` 命令中追加 `RIMO_PACKETLOGGER_APP="/绝对路径/PacketLogger.app"`（放在 `build` 前后均可），或在 Xcode 中设置同名构建变量。

构建时会验证 PacketLogger 的 Apple 签名。收音还需要 Apple 的 macOS 蓝牙日志描述文件与本机管理员授权。启用后，Siri 侧键由收音功能接管；在 Rimo 里停止收音或退出应用即可结束采集。录音保存于 `~/Library/Application Support/Rimo/Recordings/`。虚拟麦克风需从「设备设置」单独安装；该流程仍在实验阶段。

## 验证映射改动

以下测试覆盖映射读写、场景预设和继承、HID 事件去重，以及单击、双击、长按识别。无需连接遥控器即可运行。

```sh
mkdir -p .build
swiftc -o .build/remote-configuration-test \
  Tests/RemoteConfigurationTest.swift Rimo/Input/RemoteInput.swift \
  Rimo/Mapping/RemoteConfiguration.swift Rimo/Mapping/KeyboardShortcut.swift \
  Rimo/Mapping/ActionOutput.swift
.build/remote-configuration-test
```

## 项目资料

- [Rimo 品牌资源与 Figma 设计稿](docs/brand/README.md)
- [功能范围和已知限制](docs/product-scope.md)
- [A2540 收音诊断工具](Rimo/Input/VoicePrototype/README.md) 与 [回放测试](Tests/VoiceReplay.swift)
- [设备界面与验证清单](docs/device-interface.md)、[Options+ 对照记录](docs/optionsplus-main-findings.md)和 [SwiftUI 共享样式](Rimo/Settings/SettingsView.swift)

第三方资源分别遵循各自许可：[Siri Remote 3D 模型（CC BY 4.0）](Rimo/Resources/SiriRemote-LICENSE.txt)、[Geist（SIL OFL 1.1）](Rimo/Resources/Geist/OFL-Geist.txt)和 [Opus](Rimo/Resources/Opus-LICENSE.txt)。
