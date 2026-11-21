# Rimo 设计规范

**版本**: 1.0  
**最后更新**: 2026-11-21  
**范围**: Rimo macOS 应用的 UI/UX 设计系统

## 概览

Rimo 遵循 Apple 的 macOS 设计指南，采用 SwiftUI 原生组件和自定义样式系统。设计重点是清晰的信息架构、一致的交互模式和流畅的动画反馈。

## 色彩系统

### 品牌色

- **主色（Primary）**: `#007AFF`（系统蓝）- 用于按钮、链接和高亮
- **成功色（Success）**: `#34C759`（系统绿）- 成功状态和确认操作
- **警告色（Warning）**: `#FF9500`（系统橙）- 警告和注意事项
- **错误色（Error）**: `#FF3B30`（系统红）- 错误状态和销毁操作
- **静音色（Muted）**: `#8E8E93`（系统灰）- 次要文本和禁用状态

### 背景色

- **Light Mode**:
  - 主背景：`#FFFFFF`（纯白）
  - 次背景：`#F2F2F7`（浅灰）
  - 表面色：`#FFFFFF`（纯白）

- **Dark Mode**:
  - 主背景：`#000000`（纯黑）
  - 次背景：`#1C1C1E`（深灰）
  - 表面色：`#2C2C2E`（中灰）

### 语义色

```swift
extension Color {
    static let rimoAccent = Color(red: 0, green: 0.48, blue: 1)      // #007AFF
    static let rimoSuccess = Color(red: 0.2, green: 0.78, blue: 0.35) // #34C759
    static let rimoWarning = Color(red: 1, green: 0.58, blue: 0)      // #FF9500
    static let rimoError = Color(red: 1, green: 0.23, blue: 0.19)     // #FF3B30
    static let rimoMuted = Color(red: 0.56, green: 0.56, blue: 0.58)  // #8E8E93
}
```

## 字体系统

所有文本使用 **Geist** 字体族（或系统默认字体作为备选）。

### 字体大小

- **标题 (Title)**: 18pt, 600 weight - 页面和对话框标题
- **副标题 (Subtitle)**: 16pt, 600 weight - 章节标题
- **正文 (Body)**: 13pt, 400 weight - 主要内容文本
- **标签 (Label)**: 11pt, 500 weight - 按钮和标签
- **细节 (Caption)**: 11pt, 400 weight - 辅助文本和说明

### 行高

- 标题及以上：1.2 倍行高
- 正文和标签：1.5 倍行高
- 细节文本：1.4 倍行高

## 组件库

### 按钮

**主按钮（Primary Button）**
- 背景：`rimoAccent`（#007AFF）
- 文字：白色，Label 尺寸
- 圆角：6pt
- 内边距：8pt 垂直，16pt 水平

**次按钮（Secondary Button）**
- 背景：`rimoMuted` 透明度 20%
- 文字：`rimoAccent`，Label 尺寸
- 圆角：6pt
- 内边距：8pt 垂直，16pt 水平

**幽灵按钮（Ghost Button）**
- 背景：透明
- 文字：`rimoAccent`，Label 尺寸
- 边框：1pt，`rimoMuted` 透明度 30%
- 圆角：6pt
- 内边距：8pt 垂直，16pt 水平

### 输入框

- 圆角：6pt
- 边框：1pt，`rimoMuted` 透明度 20%
- 背景：浅灰（Light Mode）/ 深灰（Dark Mode）
- 内边距：10pt
- 焦点状态：边框色变为 `rimoAccent`，1pt

### Toast 通知

**布局**
- 宽度：最大 400pt
- 圆角：8pt
- 内边距：12pt
- 出现位置：屏幕右下角，距离底部 16pt，右侧 16pt

**类型**

| 类型 | 背景色 | 图标 | 持续时间 |
|------|--------|------|---------|
| Success | #D4EDDA | ✓ | 3s |
| Error | #F8D7DA | ✗ | 5s |
| Information | #D1ECF1 | ⓘ | 4s |

**示例**
```swift
enum ToastMessage {
    case mappingPaused
    case voiceReady
    case actionAssigned(action: String, from: (button: String, trigger: String), 
                       to: (button: String, trigger: String))
}

model.toasts.show(.mappingPaused)
```

### 3D 遥控器模型

**渲染**
- 视角：等轴测投影，略微俯视
- 光源：顶部偏前方
- 背景：渐变（从上方略深到下方略浅）
- 交互：拖动旋转，轻微摇晃动画

**按键高亮**
- 未分配：白色 / 浅灰（取决于主题）
- 已分配：`rimoAccent`（#007AFF）
- 活跃（按下）：`rimoAccent` 加深 20%
- 禁用：`rimoMuted` 透明度 50%

## 动画

### 时序

- **快速**（Fast）: 150ms - 按钮反馈、焦点变化
- **标准**（Standard）: 300ms - 页面过渡、视图展开
- **缓慢**（Slow）: 500ms - 模态对话框、关键状态变化

### 缓动函数

- **按钮交互**: `easeInOut`
- **页面过渡**: `easeInOut`
- **模态出现**: `easeOut`
- **模态消失**: `easeIn`

### 常用动画

```swift
// 按钮按下反馈
.scaleEffect(isPressed ? 0.95 : 1.0)
.animation(.easeInOut(duration: 0.15), value: isPressed)

// 视图淡入淡出
.opacity(isVisible ? 1 : 0)
.animation(.easeInOut(duration: 0.3), value: isVisible)

// 3D 遥控器旋转
.rotation3DEffect(rotation, axis: axis)
.animation(.easeInOut(duration: 0.3), value: rotation)
```

## 可访问性

### 对比度

- 文本与背景最小对比度：4.5:1（普通文本）
- 大文本与背景最小对比度：3:1

### 焦点指示器

- 颜色：`rimoAccent`
- 样式：1pt 虚线边框
- 圆角：对应组件圆角 + 2pt

### 屏幕阅读器

- 所有交互元素提供 `accessibilityLabel`
- Toast 通知使用 `accessibilityAnnouncement`
- 3D 模型提供 `accessibilityHint` 说明交互方式

## 布局

### 间距标准

- **极小**（XS）: 4pt
- **小**（S）: 8pt
- **中**（M）: 12pt
- **大**（L）: 16pt
- **超大**（XL）: 24pt

### 响应式设计

- **最小窗口宽度**: 800pt
- **最小窗口高度**: 600pt
- **优先宽度**: 1200pt
- **优先高度**: 720pt

### 侧栏

- 宽度：最小 200pt，最大 350pt
- 默认宽度：280pt
- 分隔线：1pt，`rimoMuted` 透明度 20%

## 主题

### Light Mode

```yaml
background: "#FFFFFF"
surface: "#F2F2F7"
text-primary: "#000000"
text-secondary: "#6F6F6F"
border: "#E5E5EA"
accent: "#007AFF"
```

### Dark Mode

```yaml
background: "#000000"
surface: "#1C1C1E"
text-primary: "#FFFFFF"
text-secondary: "#A1A1A6"
border: "#424245"
accent: "#0A84FF"
```

## 验收标准

- ✅ 所有文本可读性符合 WCAG AA 标准
- ✅ 键盘导航完全可用
- ✅ 屏幕阅读器可以访问所有功能
- ✅ Dark Mode 下所有颜色对比度符合要求
- ✅ 动画可在系统设置中禁用
- ✅ 响应时间 < 100ms

---

**维护者**: Rimo 开发团队  
**最后审查**: 2026-11-21
