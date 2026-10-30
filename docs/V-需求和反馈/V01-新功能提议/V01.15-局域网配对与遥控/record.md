# record

2026-10-30：核对最新 master、全部开放 issue 和历史回复。用户已委托维护决策、开发、合并、发布与已验证 issue 收尾。

## 2026-10-30 第二实现检查点

已实现默认关闭的局域网接收服务、六位配对码、12小时会话、撤销/轮换、mDNS与UDP发现、地址/二维码、App和内置浏览器控制端、直播链接推送，接入手机/电视/多画面播放器与电视方向/确认键。新5项真实loopback双客户端、过期/撤销、旧目标隔离、晚到链接和异常输入测试通过；修正拒绝请求未消费POST正文导致连接复用失败。原设置布局三项失败已修正并复验39通过；未修改归档基线。跨设备和浏览器/系统界面验收未完成。

所有九项需求完成后统一发版。当前未跑最终全量门禁，未推送、未发布、未关闭issue。


### 2026-10-30 Android 17 LAN runtime access correction

A final platform-permission audit found that the new playback receiver, discovery and pairing paths did not use the existing Android 17 runtime permission bridge. The manifest already declared ACCESS_LOCAL_NETWORK, but that does not grant it for target SDK 37. Android and Flutter primary documentation require permission before Dart sockets are opened: https://developer.android.com/privacy-and-security/local-network-permission and https://docs.flutter.dev/platform-integration/android/local-network-permission . The earlier API28 native acceptance could not exercise this enforcement, so that coverage gap is explicitly retained.

Three refusal regressions failed before wiring. Receiver bind, discovery and pairing now request access before network I/O; refusal remains distinct from wrong address/code and shows a LAN-specific translated explanation. Stopping while a prompt is pending invalidates late approval. All 42 integrated remote/settings/projection cases passed, followed by all 11 remote/copy cases and fatal-infos analysis after the wording correction. Tests verify no receiver/code/session/discovery side effects on refusal, retry after approval, cancellation and real UI messages; fake discovery fails before any real multicast I/O.

A new, isolated API37/x86_64 generated-data AVD displayed the actual system permission prompt. Refusal left reception off; retry and Allow started the receiver; its browser entry returned HTTP200 through an owned loopback forward, and unauthenticated status returned401. Reception was stopped, the code retired, permission restored to ungranted, forward removed and the owned AVD stopped with data preserved. This was a working-source profile, not a frozen release package; only its refusal-copy key/locale wording changed afterwards, with final-package copy/native revalidation still required. It is not physical K90 or multicast LAN acceptance. Every installer and the complete gate will be regenerated from the corrected frozen source before publication.


### 2026-10-31 Full language-parity correction

The full gate for a32ed430 rejected one i18n parity test: the new LAN-refusal sentence existed only in the two base languages, while thirteen selectable languages require the same key set. All thirteen now have localized text, preserving sorted four-space JSON and existing placeholder/line-break contracts. The complete i18n suite and the real remote-settings refusal widget test pass. No failed-source installer was built or published. Permission and playback production code did not change. The failed gate and source bundle are retained separately; the corrected source gets a fresh all/14 gate and all installers.
