# A2540 收音诊断工具

这些脚本用于排查 Siri Remote 的 HID 与蓝牙音频路径，不属于 Rimo 的 Xcode target。依赖 Swift 命令行工具、Python 3 和本机 Opus 库。若 Opus 不在 Homebrew 默认位置，可用 `RIMO_OPUS_LIBRARY` 指向 `libopus.dylib`。

## 检查 HID 音频接口

配对 A2540 后，从项目根目录运行：

```sh
bash Rimo/Input/VoicePrototype/run.sh --check
bash Rimo/Input/VoicePrototype/run.sh
```

终端提示就绪后，按住 Siri 侧键说话几秒，然后松开。成功时 WAV 路径会显示在终端，并保存在 `.build/voice-prototype/` 下。可追加 `--enable-feature` 试验已知的 `0xFF` Feature 报告；写入成功不代表收到了音频。实测能收到 Siri 键事件，但 HID 和 CoreBluetooth 诊断未取得音频帧。`build-gatt.sh` 可构建独立的只读 CoreBluetooth 诊断应用。

## 检查 PacketLogger 路径

按 [项目 README](../../../README.md#可选遥控器收音) 放置 Apple 的 PacketLogger，并配置官方 macOS 蓝牙日志描述文件。检查工具版本或运行短时采集：

```sh
bash Rimo/Input/VoicePrototype/trace-once.sh --check
bash Rimo/Input/VoicePrototype/trace-once.sh
```

采集需要本机管理员授权。按提示按住 Siri 侧键说话，松开后立即停止采集。抓包路径会输出到终端，文件留在本机。请只分析目标遥控器的流量：

```sh
python3 Rimo/Input/VoicePrototype/packetlogger.py trace.pklg --peer AA:BB:CC:DD:EE:FF
```

把示例地址替换为遥控器的蓝牙地址。若抓包中没有连接事件，可以用确认过的 `--handle` 替代 `--peer`。比较按下与松开期间的 ATT 通知；确认音频特征后，再用 `--attribute` 和 `--wav` 解码。连接句柄和特征句柄需从本次采集确定。

A2540 已通过 PacketLogger 路径采集真实音频，解码为 48 kHz 单声道 WAV 并完成回放。帧结构参考 [SiriRemoteForge 的公开协议记录](https://github.com/HOLODATA-COM/SiriRemoteForge/blob/main/HANDOFF.md)。仓库不附带原始抓包或录音。
