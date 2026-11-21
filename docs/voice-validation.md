# 语音组件离线验证

在项目根目录运行以下命令。需要 Xcode 命令行工具和静态 Opus 库；先按 [README](../README.md#从源码构建)构建应用，让后台服务测试可使用应用内打包的环境工具。若构建时使用了其他 Derived Data 目录，最后一条命令中的应用路径也要对应修改。

以下测试以当前用户运行，不需要管理员权限，不会部署 LaunchDaemon、安装 HAL 驱动或修改系统蓝牙设置。环境配置测试只在临时目录中验证写入、备份和还原。

```sh
mkdir -p .build/voice-tests

swiftc -swift-version 6 -o .build/voice-tests/session-test \
  Tests/VoiceSessionTest.swift Rimo/Voice/VoiceCapture.swift \
  Rimo/Voice/VoiceRecording.swift Rimo/Voice/PacketStream.swift \
  Rimo/Voice/MicrophoneBridge.swift "$(brew --prefix opus)/lib/libopus.a"
.build/voice-tests/session-test

swiftc -swift-version 6 -o .build/voice-tests/readiness-test \
  Tests/VoiceCaptureReadinessTest.swift Rimo/Voice/PacketStream.swift
.build/voice-tests/readiness-test

xcrun clang -std=c11 -Wall -Wextra -Wno-unused-parameter -Werror \
  -framework CoreAudio -framework CoreFoundation \
  Tests/AudioDriverTest.c -o .build/voice-tests/driver-test
.build/voice-tests/driver-test

swiftc -swift-version 6 Rimo/VoiceTools/VoiceEnvironment.swift \
  -o .build/voice-tests/voice-environment
python3 Tests/VoiceEnvironmentTest.py .build/voice-tests/voice-environment

swiftc -swift-version 6 -D HELPER_TESTING \
  Tests/VoiceHelperTest.swift Rimo/VoiceHelper/VoiceHelperMain.swift \
  Rimo/VoiceHelper/VoiceHelperProtocol.swift -o .build/voice-tests/helper-test
.build/voice-tests/helper-test .build/xcode/Build/Products/Debug/Rimo.app
```

覆盖范围包括重复音频帧、丢帧补偿、尾包收尾、断连和超时、采集启动预算、驱动属性与多客户端读取、配置备份及冲突保留，以及服务协议、固定操作校验和断开后的请求拒绝。

`Tests/VoiceCaptureTest.swift` 另需本机 A2540 采集文件，用于管道分块输入和后台工作线程回放。采集文件不提交到仓库。离线测试不能替代真机上的权限、实时收音、输入法输出、重连和睡眠唤醒验证。
