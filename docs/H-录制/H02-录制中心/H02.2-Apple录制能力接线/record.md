# H02.2 记录

2026-10-24：确认配置与能力判断不一致，先保存修改前回归。前一门禁已停止，不作为通过。


先提取原 Android/Windows/Linux 判断为按 operatingSystem 查询的纯能力函数，运行修改前回归：跟踪构建配置中 iOS/macOS 两项失败，另五项原有/无内核/当前平台检查通过。再纳入已有 Apple 包，七项能力与四项现有录制接线检查通过。没有把 UI 可用当成真实内核执行成功；隔离的 Apple native smoke 将在云端转换一秒本地 PCM→WAV 并检查退出码和 RIFF/WAVE，保留文件与回执，原自签设备继续开放。


录制能力函数、回归与云端原生入口的静态分析无问题；冻结前对正常 Apple workflow 全部 shell 步骤检查 bash 语法，正式包与独立 native smoke 使用不同 Dart 入口，证据不能混写。
