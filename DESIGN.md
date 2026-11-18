---
version: alpha
name: Logi Options+ Installer
description: 从 logic 项目安装器提炼的桌面安装体验设计系统，供 Google Stitch 和实现工具复用。
---

# Logi Options+ Installer Design System

## Overview

以产品实物为视觉重心的桌面安装体验：宽阔的中性背景、居中的设备图片、短标题和说明、一个明确的主操作。交互紫色承担安装、重试和启动等关键动作；其余区域保持平静、清晰。面向安装或修复罗技外设软件的用户，优先让用户知道当前状态、下一步动作以及错误恢复方式。

**范围与来源。** 本规范基于 Logi Options+ macOS 安装器 2.8.981479，适用于欢迎、已安装、下载、解包、安装、错误恢复及辅助对话框。它不定义主应用中的设备配置、Flow 或 Smart Actions 页面。以下“提取”表示包内资源、NIB 或静态代码支持；“适配”表示为 Stitch 生成和无障碍实现补充的规则。未验证目标应用实际运行画面。

**Stitch 使用方式。** 先生成 1200 × 680 的桌面欢迎屏，再复用同一构图生成状态变体。使用本文 YAML 作为数值来源，按说明选用组件。默认白色欢迎主题；只在指定状态使用原有紫色或深色主题。中文界面保留产品名 Logi Options+，其他文案跟随目标语言。不要自动生成导航栏、侧边栏或产品仪表盘。

**品牌资产（提取）。** 使用原始 Options+ 图标和透明背景设备图；保持比例和图片内置留白。资源目录：[Resources](logic-recovered/extracted/logioptionsplus_installer.app/Contents/Resources)。代表素材为 [Options+ 图标](logic-recovered/extracted/logioptionsplus_installer.app/Contents/Resources/welcome-LogiOptionsPlus@2x.png) 与 [设备图](logic-recovered/extracted/logioptionsplus_installer.app/Contents/Resources/DeviceImage2@2x.png)。品牌字体见同目录 Fonts，不能重新绘制标识或用通用图标代替原始设备照片。跨工具使用时需同时提供素材；本地相对链接不保证被 Stitch 自动读取。

## Colors

**提取色板。** Lila 紫 #814EFA 是主按钮填充及白色主题链接色；白色按钮文字与它配对。深墨色 #222425 用于说明和深色背景，黑色用于欢迎标题。蓝、青、荧光黄主要用于进度阶段，不扩散成页面背景。Bright Lila 是已有品牌色，未确认其原始 hover 用途，因此不自动把它当作按钮 hover 色。

**语义映射（适配）。** 为提取颜色赋予以下角色；错误红用于图标与强调，错误原因仍使用深色正文。#A5A5A5 是禁用/非关键装饰色，不能承担白底上的必要小字。深色主题使用白字，灰色背景与灰字不交叉滥用。透明黑是遮罩候选，遮罩应用方式属于适配。

```yaml
colors:
  primary: "#814EFA"
  on-primary: "#FFFFFF"
  secondary: "#434546"
  on-secondary: "#FFFFFF"
  tertiary: "#222425"
  neutral: "#FBFBFB"
  surface: "#FFFFFF"
  on-surface: "#222425"
  heading: "#000000"
  on-surface-muted: "#6F7171"
  surface-container: "#F9F9F9"
  surface-container-high: "#EEEEEE"
  outline: "#E1E2E3"
  disabled: "#E6E6E6"
  on-disabled: "#434546"
  inverse-surface: "#222425"
  on-inverse-surface: "#FFFFFF"
  progress-blue: "#00B8FC"
  progress-cyan: "#00EAD0"
  progress-yellow: "#DCFD00"
  error: "#FF2947"
  on-error: "#222425"
  legal-text: "#2F3132"
  legal-link-hover: "#006991"
  scrim: "#00000066"
```

## Typography

**提取。** 原生标题为 BrownPro Bold 32；常规操作为 BrownPro Bold 14；轻量辅助按钮为 BrownPro Light 13；白色主题说明为 BrownPro Light 14。HTML 协议正文为 16 / 22，内容标题为 48，次级标题为 24 和 20。HTML 的大标题仅属于长文内容，不用于安装主屏。

**适配。** 下列原生文字行高是为网页落地补齐的排版值，未声称是原始行高。数字进度使用等宽数字特性以减少跳动；辅助正文和表格的 13/14 级沿用现有字号形成可用层级。字体 token 使用家族名 BrownPro，按 fontWeight 映射本地 Light、Regular、Bold 文件。缺少字体时回退 Arial、系统无衬线；中文回退 PingFang SC / Noto Sans CJK SC，不模拟粗细、不拉伸字符。

```yaml
typography:
  headline-lg:
    fontFamily: BrownPro
    fontSize: 32px
    fontWeight: 700
    lineHeight: 1.25
  headline-md:
    fontFamily: BrownPro
    fontSize: 24px
    fontWeight: 400
    lineHeight: 1.08333
  headline-sm:
    fontFamily: BrownPro
    fontSize: 20px
    fontWeight: 400
    lineHeight: 1.2
  body-md:
    fontFamily: BrownPro
    fontSize: 14px
    fontWeight: 300
    lineHeight: 1.5
  body-sm:
    fontFamily: BrownPro
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.5
  label-md:
    fontFamily: BrownPro
    fontSize: 14px
    fontWeight: 700
    lineHeight: 1.25
  label-sm:
    fontFamily: BrownPro
    fontSize: 13px
    fontWeight: 300
    lineHeight: 1.4
  progress-value:
    fontFamily: BrownPro
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.5
    fontFeature: '"tnum" 1'
  legal-body:
    fontFamily: BrownPro
    fontSize: 16px
    fontWeight: 300
    lineHeight: 22px
  legal-display:
    fontFamily: BrownPro
    fontSize: 48px
    fontWeight: 700
    lineHeight: 1
    letterSpacing: -1px
```

## Layout

**桌面基线（提取）。** 主窗口内容为 1200 × 680，主标题、正文和动作在同一中心轴。设备图层的归档尺寸为 800 × 320；说明与隐私区域宽 736；进度轨道宽 300；spinner 为 32 × 32。原生按钮最小宽 140、高 40，主次按钮垂直间隔 8。正文与标题、进度等间距包含 8、10、16、20；这里保留这些值，不强行改为统一 8 点网格。

**结构（提取 + 适配）。** 上部保留大面积产品展示，中下部安排标题、说明、可选同意复选框和主次操作，隐私说明位于动作区之后。以 NIB 的布局关系为参考，不直接将 AppKit 左下原点坐标复制为网页顶部坐标。文字换行时扩展内容高度，不能固定裁切为归档中的 40 高度。

**响应式（适配）。** 桌面外层居中，最大宽 1200；宽屏不横向拉伸设备图。低于 800 的画布转为单列，左右内边距 24，设备图宽度不超过容器，文字左/右边界一致，操作区仍居中。窄屏控件点击区域至少 44 高；这覆盖原生 40 高值，属于适配。长文与报告详情可独立滚动，短状态屏保持单屏。移动端布局未从原包恢复。

```yaml
spacing:
  xs: 8px
  consent-gap: 10px
  sm: 16px
  md: 20px
  mobile-inset: 24px
  lg: 32px
  legal-inset: 40px
  xl: 48px
  window-width: 1200px
  window-height: 680px
  copy-width: 736px
  device-width: 800px
  device-height: 320px
  progress-width: 300px
```

## Elevation & Depth

**提取。** 设备素材自身包含光影和裁切，原生还有设备投影处理；界面状态主要通过背景、文字、图片和控件显隐区分。不要在已有素材阴影外重复叠加大面积黑色光晕。

**适配。** 内容保持平面，不给每段文字添加卡片。报告、协议和确认框使用独立白色表面；网页模拟模态时使用 scrim 遮罩，轻量边界即可。原生窗口阴影参数没有完整恢复，不规定一组冒充原始值的 CSS shadow。深色和紫色是已有主题能力，不能据此声明完整自动暗色模式已实现。

## Shapes

**提取。** 主按钮圆角为 4；进度条使用圆弧端帽。设备透明 PNG 保留轮廓，Options+ 图标的圆角和阴影保留在原图中。

**适配。** 辅助按钮、输入框和报告表格沿用克制的 4 圆角；内容表面使用直边。不要将所有组件改成胶囊；full 仅用于进度轨道。对话框外轮廓由宿主窗口体系决定，不从应用图标推导 24 或 32 的大圆角。

```yaml
rounded:
  none: 0px
  sm: 4px
  full: 9999px
```

## Components

### Buttons

**提取。** 主按钮紫底白字，BrownPro Bold 14，最小 140 × 40、圆角 4；次级样式包含白底紫字、浅灰底黑字和透明底黑字。英文操作使用原文大写，中文不添加字间空格。按钮宽度随翻译增加，不能为了保持 140 宽裁切文本。

**状态规则（适配）。** 保持相同背景的 hover/pressed，用边界或轻量明度变化反馈，不直接切换成低对比的 bright purple。键盘 focus 显示 2px 主色外环并与按钮留 2px 间隔。禁用状态不可触发，不能仅依赖变灰解释原因；等待协议勾选时在同意文案中说明前置条件。Stitch 版本将禁用文字设为 #434546，优先可读性；原始 #A5A5A5 仍记录为提取色，不作为该适配组件的文字色。

### Progress and status

**提取。** 显示百分比、速率/剩余量和重试倒计时；进度颜色按蓝 → 青 → 紫 → 荧光黄 → 紫切换，轨道为浅灰。750ms 旋转 spinner 表示忙碌，不用于伪装真实百分比。下载、解包、安装采用不同标题。

**适配。** 已知进度使用数值，未知进度使用 spinner；保持标题与动作位置稳定。完成后才切换到启动操作。减少动态效果时以静态图标和文字替代连续旋转，进度值正常更新。不新增未验证的自动轮播速度、庆祝特效或倒计时跳转。

### Consent, dialogs, and reports

**提取。** 必要时显示协议复选框，未勾选禁用安装；协议和隐私链接可打开本地 HTML。通用提示框提供一个或两个明确操作；重装必须区分保留设置和清洁重装。崩溃报告支持展开详情、发送、不发送；错误日志报告包含反馈输入、日志文件名、位置/文件夹列、打开位置和发送/取消。

**适配。** 模态进入时聚焦标题或首个合理控件，循环管理键盘焦点，关闭后回到触发位置。输入错误保留已填内容，失败时提供可执行的重试；不可将发送按钮点击直接呈现为发送成功。技术日志使用可滚动区域，不挤占主操作。关闭未完成反馈时使用丢弃确认；清洁重装明确说明设置影响。

```yaml
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.label-md}"
    rounded: "{rounded.sm}"
    height: 40px
  button-secondary:
    backgroundColor: "{colors.neutral}"
    textColor: "{colors.primary}"
    typography: "{typography.label-md}"
    rounded: "{rounded.sm}"
    height: 40px
  button-quiet:
    backgroundColor: "{colors.surface-container}"
    textColor: "{colors.heading}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.sm}"
    height: 40px
  button-disabled:
    backgroundColor: "{colors.disabled}"
    textColor: "{colors.on-disabled}"
    typography: "{typography.label-md}"
    rounded: "{rounded.sm}"
    height: 40px
  progress-track:
    backgroundColor: "{colors.outline}"
    rounded: "{rounded.full}"
    width: "{spacing.progress-width}"
  progress-fill-blue:
    backgroundColor: "{colors.progress-blue}"
    rounded: "{rounded.full}"
  progress-fill-cyan:
    backgroundColor: "{colors.progress-cyan}"
    rounded: "{rounded.full}"
  progress-fill-purple:
    backgroundColor: "{colors.primary}"
    rounded: "{rounded.full}"
  progress-fill-yellow:
    backgroundColor: "{colors.progress-yellow}"
    rounded: "{rounded.full}"
  supporting-copy:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface-muted}"
    typography: "{typography.body-md}"
  spinner:
    width: 32px
    height: 32px
  dialog:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    padding: "{spacing.lg}"
  dialog-scrim:
    backgroundColor: "{colors.scrim}"
  feedback-input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body-md}"
    rounded: "{rounded.sm}"
  legal-content:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.legal-text}"
    typography: "{typography.legal-body}"
    padding: "{spacing.legal-inset}"
  legal-link-hover:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.legal-link-hover}"
    typography: "{typography.legal-body}"
```

### Screen recipes

| 屏幕 | 内容顺序与动作 | 证据边界 |
|---|---|---|
| 欢迎 | 设备/品牌图 → 欢迎标题 → 协议说明 → 必要时同意框 → 安装 → 隐私链接 | 提取；具体图片选取需按目标状态指定 |
| 已安装 | 已安装说明 → 启动 Options+ → 重装入口 | 提取；重装分支说明设置影响 |
| 下载/解包/安装 | 阶段标题 → 说明 → 进度/忙碌状态 → 允许的取消/退出动作 | 提取；各阶段操作可用性按业务确定 |
| 网络/空间/认证错误 | 状态图 → 简短原因 → 恢复说明 → 重试或退出 | 提取；红色不承担唯一错误提示 |
| 清理失败 | 原因 → 需手动处理的路径 → 操作说明 → 再试 | 提取；路径区可滚动属于适配 |
| 协议/隐私 | 内容标题 → 可滚动正文 → 关闭 | 提取 |
| 报告 | 说明 → 可展开日志或反馈表单 → 隐私链接 → 发送/不发送或取消 | 提取；不要预填虚假的反馈或成功结果 |

## Do's and Don'ts

- Do：每屏突出一个当前主动作；同一状态沿用统一中心轴、品牌字体和 4 圆角。（提取 + 适配）
- Do：白底小字使用 on-surface 或 on-surface-muted；按 WCAG AA 核对最终渲染对比度。禁用控件例外不扩展到正文。（适配）
- Do：使用原包图片、字体和本地化文案；让中文、多行和长翻译自然扩展布局。（提取 + 适配）
- Do：保留下载、解包、安装、失败与重试的区别，使用真实进度与真实结果。（提取 + 适配）
- Don't：把协议页的 48/72 大标题和 CSS 规则套到整个原生窗口。（提取边界）
- Don't：添加玻璃卡片、背景装饰渐变、胶囊按钮、悬浮侧栏或多卡片仪表盘。（适配约束）
- Don't：把 error 红用于白字小按钮，或把低对比灰色用于必要说明。（适配约束）
- Don't：把素材内置留白裁掉、重复添加阴影、拉伸设备图片，或把实物照片改成通用 3D 插图。（提取 + 适配）
- Don't：把本规范的窄屏、focus、输入框/对话框适配参数说成原应用已验证的行为。（证据边界）

### Provenance and maintenance

本文件遵循 Google 的 [DESIGN.md alpha 规范](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)，采用唯一的顶层 YAML 分组和可解析语义引用。日期：2026-11-17。数值基线来自 [NIB 对象图](logic-recovered/decoded/interface-builder-graph.json)、[ARM64 指令](logic-recovered/native/arm64-disassembly.asm)、[按钮样式](logic-recovered/decompiled/ui/functions/0x10001347c.c)、[UI 配置](logic-recovered/decompiled/ui/functions/0x100029fa4.c)、[进度样式](logic-recovered/decompiled/ui/functions/0x100012fac.c) 和 [协议 CSS](logic-recovered/extracted/logioptionsplus_installer.app/Contents/Resources/styles.css)。完整提取边界见 [覆盖报告](logic-recovered/analysis/覆盖报告.md)。新增主应用页面前应取得对应证据并更新范围；不得用本规范补写未提取的功能。
