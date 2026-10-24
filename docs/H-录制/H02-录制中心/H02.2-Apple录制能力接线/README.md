# H02.2 接 H02.1：Apple 录制能力接线与原生内核验证

来源：[issue #42](https://github.com/wzgrx/PureLive/issues/42)，iPhone 16 Pro Max 自签版总提示没有录制内核。pubspec 已配置并由 Apple 工作流拉取、嵌入 iOS/macOS FFmpeg 包；但 recording_platform.dart 的 platformHasFfmpeg 只列 Android、Windows、Linux，导致 ffmpeg 注入 null、录制器根本不创建。该能力判断与实际构建配置矛盾，可直接解释提示，不归因于自签权限。

提取保持原行为的平台判断并保存 Apple 配置回归 RED，再把已有 Apple 包接入同一录制器；不改录制参数、存储、设置键、后台策略或重试。能力回归以跟踪的构建清单为独立依据；Apple 云端另用本地合成 PCM 执行真实内核并检查 WAV，不访问平台。原自签 iPhone 的真实直播、停止、导出和后台仍需原设备验收。
