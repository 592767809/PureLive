# V02.53 电视独立设置页统一

来源：[#61](https://github.com/wzgrx/PureLive/issues/61)。

## 评估

两张截图已逐张查看：普通分类有自定义背景与白框，IPTV为通用AppBar且背景覆盖。tv_router对独立页只包TvSettingsStyle，未统一使用TvSettingsScaffold；须逐页核对七页的首焦点、首项Up边界/滚动、标题返回和壁纸透明策略，不能将单一页面样式修补当七页验收。

## 代码入口

- [tv_router.dart](../../../../apps/pure_live/lib/routes/tv_router.dart)
- [tv_settings_section_page.dart](../../../../apps/pure_live/lib/tv/settings/tv_settings_section_page.dart)
- [tv_settings_style.dart](../../../../apps/pure_live/lib/tv/settings/tv_settings_style.dart)

## 当前进度

5.4.17冻结范围后到达，仅评估登记并回复，保持issue开放；没有计入本版已修复，也尚未完成原机验收。
