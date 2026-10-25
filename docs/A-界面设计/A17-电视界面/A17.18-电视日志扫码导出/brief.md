# A17.18 电视日志扫码导出

## 范围与基线

电视日志导出复用现有PhoneBridge，发送完整导出文本到扫码查看流程；手机/iOS系统分享与当前筛选复制入口保留，避免进入Sony系统分享目标选择器。

来源：https://github.com/wzgrx/PureLive/issues/54。按D-003沿用已确认的界面组件和操作，修复已有契约差异。先读AGENTS.md、docs/PROCESS.md、docs/specs/ENGINEERING.md、docs/specs/UI.md和相关既有任务；生产播放、平台请求、账号和迁移语义不改。

## 源码与允许修改

apps/pure_live/lib/features/backup/log_page.dart；shared/phone_bridge.dart；platform/plugins.dart；app/app_log.dart；tv/phone；test/features/backup；test/tv。跨模块只改必要的页面构造、导航和应用内导出入口；共用组件保持默认行为兼容，测试只用生成数据。

## 验收

新增有意义的旧代码失败回归，保留首次失败与根因；定向测试、fatal-infos和完整all/14通过。测试定时器至少1秒，不访问真实平台。窗口大字、返回和旧入口回归按各任务具体场景覆盖。K90仅操作v4dev；原机和真实分享目标另留范围边界，真实日志、二维码与账号不得入仓库或发往外部应用。

## 当前进度

已登记，尚未修改本任务运行时代码；PR #55的原始提交保留在本地非快进合并中，另行审查和验证，当前不视作完成。
