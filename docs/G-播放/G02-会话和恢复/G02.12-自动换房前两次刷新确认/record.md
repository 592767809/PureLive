# record

2026-10-30：核对最新 master、全部开放 issue 和历史回复。用户已委托维护决策、开发、合并、发布与已验证 issue 收尾。

## 2026-10-30 实现检查点

五项能力已接入；#115修复前失败已保留，新增暂停/取消边界回归；#108独立正负dB与默认继承、多画面复用回归通过；#106四种手势回归通过；#110十三项焦点回归通过。三成员静态分析通过，修改后的四组界面/自动切房集成107项通过。完整门禁、所有九项需求和最终原生验收未完成，当前不推送、不发布、不关闭issue。

## 真实句柄的跨实例阻塞回归

#33新日志在已取到详情/清晰度/地址后出现`engine_create_timeout`。重新检查底层分支发现`NativePlayer.lock`为静态锁，所有实例的创建、控制、停止、释放共用队列。旧内核停止回包未完成时，即使会话已隔离旧内核，替换内核仍无法初始化。[实际采用的上游代码](https://github.com/Predidit/media-kit/blob/6b188ae978808a63e5b58b7ce61f7725238c04c5/media_kit/lib/src/player/native/player/real.dart)也保留此静态锁；[mpv内部设计说明](https://github.com/mpv-player/mpv/blob/master/DOCS/tech-overview.txt)要求实例内部正确同步，并允许不同实例独立工作。

新增真实mpv句柄回归：在旧实例释放中扣住停止回包，要求替换实例在旧回包放行前完成初始化、音量控制和暂停。原实现稳定在2秒截止时间失败；改为实例锁后通过，原有每个句柄的操作顺序和事件缓冲区所有权保持。包括已有恢复、Android Surface和异步属性回归的16项及全部117项播放器测试通过。该证据确认公共代码缺陷，不代表原Huawei/Sony/Honor已验收，#33/#49继续开放。


### 2026-10-30 Native projection navigation correction

The exact 4d53681 Windows ZIP played a real generated stream in its owned fullscreen projection process. Selecting a second cell and a direct authenticated room command returned successfully but retained the first room. The production receiver replaced its sole home route on the first command; subsequent root replacements shared a GoRouter page key and retained the existing StatefulWidget/player. A real-router widget regression reproduced the stale room before the fix. The receiver now pushes its first room above home, then replaces only that room, preserving a base route and fresh room state. Four navigation/IPC tests and six-member fatal-infos analysis pass. All packages and the complete gate will be regenerated for this correction; old artifacts remain preserved outside the repository. No original-device acceptance is claimed.
