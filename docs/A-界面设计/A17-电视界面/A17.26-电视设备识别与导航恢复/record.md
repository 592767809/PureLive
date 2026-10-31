# A17.26 电视识别与导航记录

- Dart原来的平台调用异常会永久缓存false；新增可重试失败、已确认电视的正向锁定与恢复时provider更新，首帧/恢复再次核对；用户显式手机选择保持优先。
- 原生原本已有UI_MODE_TYPE_TELEVISION与FEATURE_LEANBACK；补充设备电视特征/配置及仅保存已确认电视的身份，不声称原实现遗漏leanback。
- 设置嵌套Navigator的方向边界改为parentScope；共享设置Slider使用directional导航，使上下离开、左右调整。旧行为反例与恢复/覆盖策略回归通过。
- Sony KD-65X8566E未接入本轮，不据模拟器推断其具体SoC、网络或原机长时间断电根因。最终受控电视布局、重启和导航验证见Y01.39。

状态：源码候选待最终门禁与原生验收，未公开发布。发布与元数据收尾见Y01.39。

## 电视原生导航发现的第二层焦点问题

API28电视模式实测发现上下可移焦，但左右没有调节滑块。通过仅受控AVD的VM对象检查，实际焦点在无onTap的外层InkWell；Flutter方向导航下该控件忽略canRequestFocus，导致单测直接聚焦滑块时漏检。新增按真实directional导航进入滑块的反证测试，改前0.5不变而失败；SettingsRow显式将无动作外层FocusNode标为skipTraversal，保留滑块与计数器的内部焦点，修复后34项设置及焦点回归通过。原生新构建复验仍待进行，不能将旧试包当最终源码。

上游依据：[Flutter InkWell实现](https://flutter.googlesource.com/mirrors/flutter.git/+/refs/heads/main/packages/flutter/lib/src/material/ink_well.dart)方向导航分支返回true；[焦点说明](https://docs.flutter.dev/ui/interactivity/focus)区分skipTraversal和canRequestFocus。修复不修改共享Flutter SDK。

受控API28最新开发试包复验：设置首行上键已停留、回顶标题恢复，滑块左右50%→55%→50%、上下切换全局静音和音量增强均成功。另发现播放信息页经内部链接打开时未继承TV样式及初始焦点；以及1280×720下内部Slider可见而整行描边仍裁切12像素。新增实际TV路由和相同尺寸的反证均失败后，HUD页使用TV设置壳、共享设置正文约束及首焦；TV滚动在整行可容纳时显示完整SettingsRow，超高行保留其当前控件。七项相关回归通过，最新原生构建复验待进行；不把试包视为正式同源包。
