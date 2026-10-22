# Y01.18 候选收尾记录（2026-10-22）

## 来源

独立仓库 `/home/wzgrx/projects/purelive-codex`，分支 `ai/V02.14`。生产代码候选 `dbd1f71fcdd4bfe00095f955241fd4b9cfa5c5d2`，tree `31318055b71392771a430e29450017d9c25db55b`。后续仅补文档，不改变构建来源。原 `.claude` 工作区和十个未提交文件保持原状。

## 构建与校验

- 全量门禁：all，14 members，通过；音量定向 4/4，新增两处边界修复前失败。
- Android 三 ABI release：包名 `com.mystyle.purelive`，版本 5.4.7，versionCode 为 7111、6111、9111，证书与旧版一致；通知图标、ZIP/ELF 对齐、FFmpeg b2 校验通过。32 位 ARM 采用 4 KB ELF 最小对齐；16 KB 原生要求检查用于 arm64 和 x86_64，未将二者混用。正式包未安装到 K90。
- Windows：本机相同工具链构建 setup 与 portable；便携包实际进入首页、真实直播播放与音量交互通过。setup 未安装，不操作原安装。
- Linux：本机 release、tar.gz；私有 Xvfb、隔离 XDG 数据，实际进入首页，保存截图，退出仅本次进程。
- Apple：[运行 39758808679](https://github.com/wzgrx/PureLive/actions/runs/39758808679) 在上述同一提交成功。四个包及其 SHA-256 保留在 GitHub artifact；核对 macOS 与 iPhone 模拟器截图均进入首页。遵循 D-041，没有下载四个包到本机。
- Android 原生依赖首次下载出现 TLS 失败，只复用经目录内 SHA-256 核对的原生压缩归档，不复用旧构建产物，重建通过。WSL 中途退出原因未证实；未执行关闭或重置 WSL，恢复后完成中断的 profile 构建。

## K90

用户独立授权只操作 v4dev，经过前台守卫。A01.8 竖屏效果、质感禁用、紧凑底栏和两轮原始帧测量通过，见对应 record/verify。深色 100% / 50%：2094 / 2085 帧，raster P90 3.114 / 3.064 ms，阶段超预算 0.5731% / 0.4796%。最后恢复普通 profile、原外观偏好和旋转，保留全部测试数据。

## 停在哪

PR [#13](https://github.com/wzgrx/PureLive/pull/13) 可审核；六个本地正式候选和四个 Apple 候选已构建，交付目录有十包 SHA256SUMS。已创建未公开的 GitHub 发布草稿，六个本地包、校验文件和同次 Apple 构建资产按流程挂入；最终完整性以远端资产清单核验为准。没有合并 master、打 v5.4.7 标签、公开发布、修改两仓库更新通道或回复 issue。更新通道保持 5.4.6。

剩余真实验证：电视遥控器、K90 横屏及三键导航、真实持续按住桌面滑块、Linux/macOS 音量、Apple 真机与 Windows setup。保留原有发布说明限制，不将本轮冒烟扩大为全平台业务验收。下一步由维护者审核 PR 和上述空白，批准后按任务书完成发布。
