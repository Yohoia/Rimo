# Rimo 品牌资源

新版品牌以用户提供的紫色应用图标为准：白色遥控器主体、圆环与一条短横线。

- [Figma 设计稿](https://www.figma.com/design/0UP0Tpsjf3X6tr0Nzmk9xO/Rimo)：母版、页面图标、菜单栏和 Dock 四组资产。
- [原始参考图](Rimo-reference.png)：完整保留上传图片，用于核对光影与比例。
- [Dock 可编辑 SVG](Rimo-dock.svg)：透明画布，保留紫色底板、珠光主体与渐变，适配 macOS 图标留边；这是按原图重建的矢量版本。
- [单色标志 SVG](Rimo-symbol.svg)：遥控器轮廓和圆环、短横线留空，供页面和菜单栏使用。
- [Rimo 字标 SVG](Rimo-wordmark.svg)与[组合标志 SVG](Rimo-lockup.svg)：直接从 Figma 新版母版导出。

应用图标的 16、32、64、128、256、512、1024 px PNG 已同步到 Xcode Asset Catalog。菜单栏使用 18 pt 透明模板图标，提供 18 px @1x 与 36 px @2x 资源。首页左上角显示「欢迎回来」，不展示 Logo。

本地完整导出包位于 `icon-exports/Rimo-logo-export.zip`，包含 SVG 母版、透明 PNG、菜单栏模板和 `Rimo.icns`。SVG 与 PNG 均已移除 Figma 导出的页面底色；Dock 保留 100 px 透明留边。

品牌统一写作 **Rimo**；Xcode 工程、scheme 和应用产物名称均为 Rimo，Bundle ID 为 `cn.yohoia.rimo`。首次启动时会读取旧 Bundle ID 的映射配置，已有 Rimo 配置优先。旧版录音仍保留在原来的 Application Support 目录；当前版本不再保存录音。虚拟麦克风的新名称为 `Rimo Remote Microphone`；启用遥控器语音时会自动安装新版驱动。
