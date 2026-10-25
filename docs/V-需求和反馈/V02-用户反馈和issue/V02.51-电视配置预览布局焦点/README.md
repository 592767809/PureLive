# V02.51 电视配置预览布局焦点

来源：[#59](https://github.com/wzgrx/PureLive/issues/59)。

## 评估

截图已查看：配置预览在右栏、左侧仍为设置总览。代码确认电视入口将configPreview转到通用SettingsPage，该页按840断点走双栏；需要改为电视全页并覆盖长JSON树遥控滚动、返回及焦点。当前是代码路径与截图吻合的线索，未在Sony原机验证。

## 代码入口

- [tv_settings_catalog.dart](../../../../apps/pure_live/lib/tv/settings/tv_settings_catalog.dart)
- [settings_page.dart](../../../../apps/pure_live/lib/features/settings/settings_page.dart)
- [data_tools.dart](../../../../apps/pure_live/lib/features/settings/data_tools.dart)

## 当前进度

5.4.17冻结范围后到达，仅评估登记并回复，保持issue开放；没有计入本版已修复，也尚未完成原机验收。
