# Rimo

Rimo 是一款用 Apple TV Siri Remote 控制 Mac 的 macOS 应用。你可以为遥控器按键分配快捷键、媒体控制、鼠标操作和其他动作，也可以按 App 使用不同的映射。首要实测机型为 **A2540**。

## 功能

- **首页**：左上角显示「欢迎回来」，点击返回首页；右上角进入场景、快捷指令、暂停映射和设备设置。中央展示静止的遥控器，下方显示电量和蓝牙连接信息；悬停时鼠标旁显示「点击进入」，尖端有轻微波纹，设备不再上移。点击设备进入可旋转的 3D 映射页，详情与首页共用垂直定位基准。未连接时设备灰显并禁用交互。电量优先读取 macOS 配件电源信息，HID 作为回退；暂未读取到数据时显示「电量未知」。
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
3. 回到首页点击遥控器，再点 3D 模型上要配置的键。在右侧「动作」侧栏搜索动作或展开分组。每行动作右侧默认显示一种触发方式：一个圆点代表单击，两个圆点代表双击，短横代表长按。鼠标仅悬停到行尾符号按钮区域或用键盘聚焦时展开三个选项，点击后选中底块滑到对应位置，移出后收拢为当前符号。已绑定为紫色，未绑定默认显示灰色单击符号；悬停不会改变映射。
4. 同一配置范围内，一个动作只能绑定到一个按键的一种触发方式。给它选择新的按键或触发方式，会自动解除旧绑定；全局与各 App 场景分别计算。动作列表不在行下展开设置，录制快捷键或选择 App 等需要输入的动作使用单独的配置窗口。按 Esc 或点左上角返回箭头收起侧栏。
5. 例如，把「播放 / 暂停」的单击设为「键盘 → 回车」，即可按实体按键试用。映射在任何窗口中都能执行，包括 Rimo 设置窗口，方便设置后直接确认效果。

首页与菜单栏的「暂停映射」同时停止按键映射和遥控器语音，清除待触发按键及音频缓冲；暂停期间按 Siri 键、修改映射或切换 App 都不会重新收音。恢复后仅在仍有启用的 Siri 语音快捷键映射时重新启动语音链路。暂停不影响设备连接与按键诊断，也不保证拦截 macOS 自身的按键响应。

如需为某个 App 单独配置，点击设备详情右上角的「添加应用程序」，在右侧栏多选 App，顶部全局映射右侧实时显示已选 App 图标，再点击确认。支持的 App 使用默认场景预设，其他 App 从全局映射开始，并为未设置的按键补齐通用单击动作；系统 App 默认列出 Safari、预览、图书、音乐、QuickTime Player、TV、播客、照片、访达、备忘录和终端，其余可从文件夹手动添加。添加后点击顶部的 App 图标，在 3D 遥控器上编辑该场景，并在「场景」页开启自动切换。目前 Rimo 使用被动监听，部分按键可能仍会同时触发 macOS 原有动作。其他机型尚未验证。

### 权限列表中没有 Rimo，或映射没有效果

蓝牙显示「已连接」只代表发现了设备；读取按键仍需要输入监控，发送键盘映射还需要辅助功能权限。删除过权限条目，或从多个构建目录运行 Rimo 时，请按下面的步骤核对：

1. 在「系统设置 → 隐私与安全」中打开「输入监控」或「辅助功能」（部分系统为「设备控制和数据访问」），点列表下方的「＋」，按提示使用 Touch ID 或密码验证。
2. 在应用选择窗口按 `⌘⇧G`，输入**当前运行的 Rimo.app 的完整路径**，回车后点「打开」。上面的源码构建命令生成 `<项目目录>/.build/xcode/Build/Products/Debug/Rimo.app`；若使用其他 `-derivedDataPath`，请对应替换。`.build` 是隐藏目录，应用不会自动出现在「应用程序」文件夹中。
3. 开启 Rimo 的开关；两个权限列表都需要检查。退出并重新打开同一份 Rimo，确认应用内显示「已允许」。重新构建后也要重启应用，正在运行的旧进程不会自动加载新代码；若权限失效，重新添加当前构建。
4. 确认映射未暂停、未处于快捷键录制中，对应按键的单击／双击／长按配置已保存且启用。开启场景自动切换时，还要核对目标 App 当前生效的映射。

可以在 Rimo 设置窗口内直接按实体遥控器验证映射。模型高亮只说明读取到了按键；Fn 的实际效果取决于 macOS 或输入法的快捷键设置，「调度中心」等系统动作也需要对应系统快捷键已启用。

## 技术架构

Rimo 使用纯 Swift + SwiftUI 构建，核心架构分为以下模块：

### 输入处理（Input）
- **HIDMonitor**: IOKit HID 设备管理，监听按键事件和设备状态
- **RemoteInput**: 按键事件解析和触发识别（单击/双击/长按）
- **A2540Input**: A2540 遥控器的按键定义和 HID 报告解析

### 映射系统（Mapping）
- **RemoteConfiguration**: 按键映射配置的序列化和验证
- **ActionOutput**: 将映射动作转换为系统事件（CGEvent、媒体键、系统快捷指令）
- **MappingView**: 3D 遥控器模型和映射编辑界面

### 语音捕获（Voice）
- **VoiceController**: 语音捕获生命周期管理
- **VoiceCapture**: Opus 编解码和音频流处理
- **VoiceHelperServer**: 特权 XPC 服务，提供虚拟麦克风
- **MicrophoneBridge**: CoreAudio 音频会话和输入控制

### 应用核心（App）
- **RimoModel**: 应用主状态管理（设备、映射、语音、权限）
- **RimoToastCenter**: Toast 通知中心
- **RimoToastMessage**: 类型安全的 Toast 消息枚举

### UI 层（Settings）
- **SettingsView**: 设置主界面和导航
- **DevicePage**: 设备连接、权限管理和语音组件安装
- **ScenesPage**: 场景管理和预设应用
- **ShortcutsPage**: 系统快捷指令集成

## 项目文档

- **[DESIGN.md](DESIGN.md)**: UI/UX 设计规范和视觉系统
- **[IMPROVEMENTS.md](IMPROVEMENTS.md)**: 最近的代码审查和改进报告
- **[docs/product-scope.md](docs/product-scope.md)**: 产品功能范围和设计决策
- **[docs/device-interface.md](docs/device-interface.md)**: A2540 设备接口和协议文档
- **[docs/voice-validation.md](docs/voice-validation.md)**: 语音捕获验证方法
- **[docs/action-mapping-catalog.md](docs/action-mapping-catalog.md)**: 完整的动作映射目录
- **[docs/optionsplus-main-findings.md](docs/optionsplus-main-findings.md)**: Options+ 对比分析

## 测试

测试文件位于 `Tests/` 目录：

- **RemoteConfigurationTest**: 配置序列化和验证
- **VoiceCaptureTest**: Opus 编解码和音频流
- **VoiceSessionTest**: 语音会话状态机
- **VoiceHelperTest**: XPC 服务和权限验证
- **MappingPauseTest**: 映射暂停和恢复
- **ToastTest**: Toast 通知系统

```sh
xcodebuild test -scheme Rimo -derivedDataPath .build/xcode
```

## 许可证

本项目代码使用 MIT 许可证。设计资源和品牌素材的使用请查看 [docs/brand/README.md](docs/brand/README.md)。

---

**开发者**: Yohoia  
**构建状态**: ✅ BUILD SUCCEEDED  
**最近审查**: 2026-11-21（10 个 Bug 修复，代码质量提升）
