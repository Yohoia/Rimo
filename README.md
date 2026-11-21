# Rimo

Rimo 是一款用 Apple TV Siri Remote 控制 Mac 的 macOS 应用。你可以为遥控器按键分配快捷键、媒体控制、鼠标操作和其他动作，也可以按 App 使用不同的映射。首要实测机型为 **A2540**。

## 功能

- **首页**：左上角显示「欢迎回来」，点击返回首页；右上角进入场景、快捷指令、暂停映射和设备设置。中央展示遥控器静态图片，下方显示电量和蓝牙连接信息；点击设备进入可旋转的 3D 映射页。未连接时设备灰显并禁用交互。电量优先读取 macOS 配件电源信息，HID 作为回退；暂未读取到数据时显示「电量未知」。
- **按键映射**：浏览时遥控器轻轻摇摆，也可拖动旋转。点击模型上任意按键，视图会放大按键区域，显示全部实体按键的轮廓，未分配时为白色、已分配时为主题色，并打开可搜索、可折叠分组的动作侧栏。可以为同一个按键的单击、双击和长按分别配置键盘快捷键、鼠标点击、四向滚动、媒体控制、系统操作、打开 App、输入文本或系统快捷指令。快捷键支持 Fn、左右修饰键及按住至松开；每种触发可以单独停用。实体按键按下时，模型会亮起对应按键。
- **场景**：为不同 App 设置映射。开启自动切换后根据前台 App 选择已启用的场景；没有匹配时使用全局映射。
- **场景预设**：内置演示翻页、长文阅读和网页视频。在「场景 → 场景预设」选好 App 并确认按键后应用。每套预设覆盖全部实体按键的单击映射，双击和长按独立配置。右侧动作列表首项显示当前按键的映射。
- **菜单栏与 Dock**：打开设置、查看连接状态和暂停映射。
- **遥控器语音（实验性）**：把 Siri 键映射成输入法的语音快捷键（如 Fn、Option），按住说话，声音会通过 Rimo Remote Microphone 交给输入法。

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
2. 在 Rimo 的设备设置中点击「授予权限」，给当前运行的 Rimo 开启「输入监控」和「辅助功能」，分别用于读取按键和发送键盘事件。有些系统把辅助功能权限入口显示为「设备控制和数据访问」。授权后退出并重新打开 Rimo，确认设备设置中的权限均显示「已允许」。
3. 回到首页点击遥控器，再点 3D 模型上要配置的键。在右侧「动作」侧栏的标题栏选择单击、双击或长按，可搜索动作或展开分组。按 Esc 或点左上角返回箭头收起侧栏。
4. 例如，把「播放 / 暂停」的单击设为「键盘 → 回车」，即可按实体按键试用。映射在任何窗口中都能执行，包括 Rimo 设置窗口，方便设置后直接确认效果。

如需为某个 App 单独配置，点击设备详情右上角的「添加应用程序」，在右侧栏多选 App，顶部全局映射右侧实时显示已选 App 图标，再点击确认。支持的 App 使用默认场景预设，其他 App 从全局映射开始，并为未设置的按键补齐通用单击动作；系统 App 默认列出 Safari、预览、图书、音乐、QuickTime Player、TV、播客、照片、访达、备忘录和终端，其余可从文件夹手动添加。添加后点击顶部的 App 图标，在 3D 遥控器上编辑该场景，并在「场景」页开启自动切换。目前 Rimo 使用被动监听，部分按键可能仍会同时触发 macOS 原有动作。其他机型尚未验证。

### 权限列表中没有 Rimo，或映射没有效果

蓝牙显示「已连接」只代表发现了设备；读取按键仍需要输入监控，发送键盘映射还需要辅助功能权限。删除过权限条目，或从多个构建目录运行 Rimo 时，请按下面的步骤核对：

1. 在「系统设置 → 隐私与安全」中打开「输入监控」或「辅助功能」（部分系统为「设备控制和数据访问」），点列表下方的「＋」，按提示使用 Touch ID 或密码验证。
2. 在应用选择窗口按 `⌘⇧G`，输入**当前运行的 Rimo.app 的完整路径**，回车后点「打开」。上面的源码构建命令生成 `<项目目录>/.build/xcode/Build/Products/Debug/Rimo.app`；若使用其他 `-derivedDataPath`，请对应替换。`.build` 是隐藏目录，应用不会自动出现在「应用程序」文件夹中。
3. 开启 Rimo 的开关；两个权限列表都需要检查。退出并重新打开同一份 Rimo，确认应用内显示「已允许」。重新构建后也要重启应用，正在运行的旧进程不会自动加载新代码；若权限失效，重新添加当前构建。
4. 确认映射未暂停、未处于快捷键录制中，对应按键的单击／双击／长按配置已保存且启用。开启场景自动切换时，还要核对目标 App 当前生效的映射。

可以在 Rimo 设置窗口内直接按实体遥控器验证映射。模型高亮只说明读取到了按键；Fn 的实际效果取决于 macOS 或输入法的快捷键设置，「调度中心」等系统动作也需要对应系统快捷键已启用。

开发时可用下面的命令查看最近的映射执行日志。`dispatch` 说明动作进入了执行流程，最终效果仍需在屏幕上确认。

```sh
/usr/bin/log show --last 5m --style compact --info \
  --predicate 'subsystem == "cn.yohoia.rimo" AND category == "mapping"'
```

### 可选：遥控器收音

普通按键映射不依赖 PacketLogger。若要开启实验性收音，请从 [Apple 蓝牙开发者资源](https://developer.apple.com/bluetooth/) 获取官方 `PacketLogger.app`，并在构建前选择一种放置方式：

- 放到项目本地的 `.local/PacketLogger.app`，或安装到 `/Applications/PacketLogger.app`。
- 在上述 `xcodebuild` 命令中追加 `RIMO_PACKETLOGGER_APP="/绝对路径/PacketLogger.app"`（放在 `build` 前后均可），或在 Xcode 中设置同名构建变量。

构建时会验证 PacketLogger 的 Apple 签名。和 Voxa 一样，Rimo 只负责两件事：按下输入法的语音快捷键，并把遥控器的声音交给输入法，不自己识别文字。

- **Siri 键是普通按键**：默认单击是「唤醒 Siri」，可以像其他按键一样设置单击、双击、长按，也可以在场景里单独设置。
- **用遥控器说话**：把 Siri 键映射成输入法的语音快捷键，例如 Typeless 用 Fn，豆包、微信输入法用 Option。然后在输入法的设置里，把麦克风选成 **Rimo Remote Microphone**。快捷键用「触发一次」还是「按住至松开」，要和输入法的设置一致。
- **什么时候送声音**：只有当前生效的 Siri 映射（全局或场景）是单独一个修饰键时，按住 Siri 键的声音才会送到虚拟麦克风。修饰键指 Fn、Option、Command、Control、Shift，左右均可，但不能和其他键组合。如果 Siri 键映射的是唤醒 Siri 或其他动作，就不送声音。按住至松开的语音键会在松开后再等 0.3 秒才释放，避免最后几个字被截掉。
- **语音组件**：和 Voxa、RemotePilot 一样，首次引导的最后一步会请你输入一次 Mac 登录密码，装好后台采集服务、蓝牙语音配置和虚拟麦克风。不需要在「登录项与扩展」里批准，也不需要重启 Mac。这一步可以跳过，之后在 Siri 键映射成语音快捷键时，侧栏会提供安装入口。Rimo 更新了语音组件后，会自动再请求一次密码。临时签名的开发构建每次重新构建都会请求。

部署脚本（`Rimo/Resources/deploy-voice.sh`）以 root 身份运行：

- 校验 Rimo、助手、驱动和 PacketLogger 的签名，再复制到 root 所有的 `/Library/Application Support/Rimo/VoiceService/`。之后的采集不会执行用户可写的应用包里的代码。
- 注册 `cn.yohoia.rimo.voice-service` LaunchDaemon。服务只接受签名符合部署时记录要求的 Rimo 客户端：正式签名按团队匹配，临时签名按当前构建匹配。
- 备份原有蓝牙日志项，再配置实时诊断、原始音频和采集授权，关闭额外的文件日志，然后重新加载 `bluetoothd`。macOS 更新若重置了这些项，服务会自动重新配置。备份保存在 `/Library/Application Support/Rimo/VoiceEnvironment/`。若配置后采集仍被系统拒绝，可以使用 Apple 官方 macOS 蓝牙日志描述文件。
- 安装或更新虚拟麦克风后重新加载 `coreaudiod`，设备立即可用。

按住 Siri 键说话时，音频只发送到 Rimo Remote Microphone，不在本机保存录音。采集经有界管道实时读取，解析、解码和麦克风输出在后台串行执行。松键后会接收尾包，并等待输出缓冲结束；连续说话时保留上一段待输出的尾音。少量连续丢帧用 Opus 补偿，严重丢包或传输超时会结束本段并提示重试。此链路仍需更多实时收音、重连和睡眠唤醒的真机验证。

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

相机过渡回归覆盖初始全景、重复目标、动画中反向切换、旧完成回调和减少动态效果。

```sh
swiftc -o .build/remote-camera-test Tests/RemoteCameraMotionTest.swift \
  Rimo/App/RimoModel.swift Rimo/Input/*.swift Rimo/Mapping/*.swift \
  Rimo/Settings/*.swift Rimo/Voice/*.swift Rimo/VoiceHelper/VoiceHelperProtocol.swift \
  "$(brew --prefix opus)/lib/libopus.a"
.build/remote-camera-test
```

语音会话、采集就绪检查、虚拟麦克风和后台服务的离线测试见 [语音验证说明](docs/voice-validation.md)。这些测试不会安装系统服务或修改系统蓝牙设置。

## 项目资料

- [Rimo 品牌资源与 Figma 设计稿](docs/brand/README.md)
- [功能范围和已知限制](docs/product-scope.md)
- [A2540 收音诊断工具](Rimo/Input/VoicePrototype/README.md) 与 [回放测试](Tests/VoiceReplay.swift)
- [设备界面与验证清单](docs/device-interface.md)、[Options+ 对照记录](docs/optionsplus-main-findings.md)和 [SwiftUI 共享样式](Rimo/Settings/SettingsView.swift)

第三方资源分别遵循各自许可：[Siri Remote 3D 模型（CC BY 4.0）](Rimo/Resources/SiriRemote-LICENSE.txt)、[Geist（SIL OFL 1.1）](Rimo/Resources/Geist/OFL-Geist.txt)和 [Opus](Rimo/Resources/Opus-LICENSE.txt)。
