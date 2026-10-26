# Z01.3 记录

## 2026-10-26 清点

已保存初始源码 3a8b1e914、官方版本查询、pub outdated、Windows 实例和实际 CMake 选择、本机 Flutter/JDK/Gradle/Clang。独立证据目录 outputs/purelive-reassessment-20261026 不提交用户数据。旧候选未发布。

检查器只核对 JDK feature release，漏掉补丁升级；Android 包用数字路径判断稳定性而没有读取 channelRef；查询失败不导致默认退出非零。Apple 工作流固定寻找 Xcode_26，Windows 实际 CMake 来自 Visual Studio 自带目录而非 PATH。下一步补齐这些缺口并验证具体升级。

## 升级与定向验证

本机 WSL 采用独立 Temurin 27.0.1.0.2+1 与 Python 3.15.2；Windows 独立安装 Python 3.15.2、Inno 7.1.0、独立 CMake 4.4.4，原工具保留。Python 3.15.2 为 2026-10-25 官方维护发布，Windows 安装包 SHA-256 与 PSF 签名核对；WSL 官方源码 SHA-256 核对后编译，ssl/sqlite3/bz2/lzma/ctypes/venv/tomllib 导入通过。Visual Studio 18.11.2 已是官方 stable channel 当前版，Flutter 使用其附带 CMake 4.3.1-msvc1。

10 个直接依赖升级，锁文件共 48 项变化；screen_retriever 0.3 正式迁移、窗口位置快照及时释放原生句柄、不再持久化进程内 ID；window_manager 从官方发布档案引入并保留 MIT 许可，仅迁移显示器约束和工具函数。Android/Windows/Linux/macOS 生成注册清单删除旧 screen_retriever 插件。未更新原生媒体库 ABI。

检查器 Android 预发布选择在旧实现失败（误选 31.0.9，正确稳定值 30.0.1），修正后 8 项通过；增加完整 JDK、Dart、Xcode、CocoaPods、桌面工具与 Python 查询，未知查询不再成功退出。实际查询 72 项无落后、无失败。5 个传递包 cli_util、coverage、cross_file、material_color_utilities、package_config 被上游约束，保留解析器可用的最高版本，无过期/撤回/安全公告标记。

14 个成员静态分析全部通过，53 项桌面/小窗回归通过。Inno 版本探针用新 7.1.0 成功、原 6 拒绝，产物关闭，不执行安装。曾误用仓库根 dart analyze 包含历史 fixtures 和独立 third_party 测试产生 157 项诊断；保留原日志，之后按真正工作区成员检查，没有修改或掩盖历史样本。

下一步：冻结此阶段源码运行完整门禁，继续全部 issue 的独立复核；新工具链的正式跨平台构建和最终包原生验收尚未完成，当前不发布、不关闭未验证问题。

## 首轮完整门禁与本机实际版本

首轮 all/14 源码指纹一致，所有步骤除 live_danmaku 一项耗时断言通过：`/加.*群/` 在并发测试中被 2 ms wall-clock 预算判为 tooSlow。保留失败日志；未改阈值或跳过测试。随后按原命令独立重跑整个 live_danmaku，1678 项全部通过。最终推送仍必须有完整 all/14 成功，不能用单项重跑替代。

另发现 Flutter 的 jdk-dir 优先于 JAVA_HOME，旧共享配置仍指向旧 JDK。本机创建独立 XDG_CONFIG_HOME，保留共享设置；flutter doctor 实际 Java 路径和版本确认使用 Temurin 27.0.1.0.2+1。doctor 的 Android license status unknown 需继续检查，不记为全部工具链通过。跨平台原生构建开始，结果另记。
