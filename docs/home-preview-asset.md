# 首页遥控器图片

[remote-preview.png](../sofo/Assets.xcassets/RemotePreview.imageset/remote-preview.png) 是从项目的 [SiriRemote.usdz](../sofo/Resources/SiriRemote.usdz) 离线渲染的透明 PNG（460 × 1600）。

图像于 2026-11-17 使用 SceneKit `SCNRenderer.snapshot`、正交相机（scale 7）、4× 抗锯齿，以及详情页的铝外壳着色和灯光生成。SwiftUI 在首页为图片加投影和 12 点悬停偏移；运行时用 `RemotePresentation.height(in:)` 统一首页图像与详情页全景的展示高度。

来源模型作者 polyman，遵循 CC BY 4.0；作者链接及完整许可见 [模型许可](../sofo/Resources/SiriRemote-LICENSE.txt)。图片延续该模型的许可和署名。蓝牙标记位于 [BluetoothMark.imageset](../sofo/Assets.xcassets/BluetoothMark.imageset)。

首页只显示静态图，同时用近透明的视图准备 SceneKit 模型、纹理和着色器。点开设备后，等 SceneKit 首帧就绪再切换到 3D；隐藏的 3D 视图不运行空闲摇摆与呼吸光。详情页的按键推近与退出全景行为另见[设备界面](device-interface.md)。

## 电量显示

在实测 A2540 上，普通 HID 电量属性没有返回数值，而系统蓝牙设置和 IOKit 的配件电源快照都返回了电量。[HIDMonitor](../sofo/Input/HIDMonitor.swift) 会在运行时查找非公开的 `IOPSCopyPowerSourcesByType`，只有唯一匹配的已连接设备和配件电量记录才会采用这一来源；找不到符号或记录时回退至 HID。两种来源均不可用时显示「电量未知」。该路径未添加私有 entitlement，其他系统版本仍需实测。
