# Rimo 性能优化指南

## 已完成的优化

### 1. 电池电量查询缓存 (2024-11)

**位置**: `Rimo/Input/HIDMonitor.swift`

**改进**: 添加 30 秒静态缓存，减少 IOKit 设备树查询频率

**收益**: 降低 CPU 占用，减少系统资源消耗

**使用方法**: 自动生效，无需配置

---

## 性能监控工具

### PerformanceMonitor

**位置**: `Rimo/Util/PerformanceMonitor.swift`

**使用方法**:

```swift
// 同步代码测量
let result = PerformanceMonitor.measure("load-config") {
    return loadConfiguration()
}

// 异步代码测量
let data = await PerformanceMonitor.measure("fetch-data") {
    await fetchRemoteData()
}

// 标记时间点
PerformanceMonitor.mark("app-launched")
```

**启用监控**:
```bash
# 在 Xcode Scheme 中添加环境变量
RIMO_PERF_MONITOR=1

# 或在终端运行
RIMO_PERF_MONITOR=1 open -a Rimo
```

**输出**: 超过 16ms (一帧时间) 的操作会显示警告

---

## 性能优化建议

### 视图性能

**大型视图文件** (待优化):
- `MappingView.swift`: 1743 行
- `SettingsView.swift`: 981 行

**建议**: 在开发新功能时逐步拆分，不必一次性重构

**拆分策略**:
1. 识别独立的 UI 组件
2. 提取为独立的 `View` 结构体
3. 保持现有的 `@ObservedObject` 传递模式
4. 渐进式重构，每次只拆分一个组件

### 状态管理

**当前状态**: `RimoModel` 有 26 个 `@Published` 属性

**观察**: 
- 大多数属性更新不频繁
- SwiftUI 的差分机制处理良好
- 未发现性能瓶颈

**建议**: 
- 只在遇到实际性能问题时才考虑拆分
- 可以按功能分组（设备状态、语音状态、映射状态）
- 使用 Instruments 确认是否存在不必要的视图更新

### 音频处理

**当前实现**: 固定大小缓冲区，分块处理音频

**可选优化** (低优先级):
- 自适应缓冲区大小
- 基于蓝牙吞吐量动态调整
- 静默检测提前刷新

---

## 性能分析工具

### Xcode Instruments

**推荐工具**:
1. **Time Profiler**: 识别 CPU 热点
2. **Allocations**: 检测内存泄漏
3. **SwiftUI**: 视图更新分析

**使用步骤**:
```bash
# 1. 启用性能监控
RIMO_PERF_MONITOR=1

# 2. 在 Xcode 中 Product > Profile
# 3. 选择对应的 Instrument 模板
# 4. 执行性能敏感的操作
# 5. 分析结果，重点关注：
#    - 超过 16ms 的操作
#    - 频繁的小对象分配
#    - SwiftUI body 重复计算
```

### 日志分析

**Console.app 过滤器**:
```
subsystem:cn.yohoia.rimo category:performance
```

---

## 最佳实践

### 避免性能陷阱

1. **不要过度优化**: 先测量，再优化
2. **保持简单**: 清晰的代码比微优化更重要
3. **渐进式改进**: 每次只优化一个点
4. **验证收益**: 用 Instruments 确认改进效果

### 新功能开发

1. **使用 PerformanceMonitor 包装关键路径**
2. **定期运行 Time Profiler 检查**
3. **关注主线程操作**
4. **避免同步的网络/文件 I/O**

### 代码审查关注点

- [ ] 是否在主线程执行耗时操作？
- [ ] 是否有不必要的 `@Published` 触发？
- [ ] 是否可以延迟加载？
- [ ] 是否有重复的查询或计算？

---

## 参考

- [Apple Performance Best Practices](https://developer.apple.com/videos/play/wwdc2023/10160/)
- [SwiftUI Performance Tips](https://developer.apple.com/documentation/swiftui/fruta_building_a_feature-rich_app_with_swiftui)
- [Concurrency in Swift](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
