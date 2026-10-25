# V02.55 分区平台标签增加图标

来源：[#63](https://github.com/wzgrx/PureLive/issues/63)。

## 评估

手机和Windows共用AreasView，当前TabLabel只传平台名，电视另有平台标签。后续应复用既有平台图标资源，保持中文名、平台顺序、选中态及无障碍语义，并检查窄屏、大字体和横向滚动；无需新下载图标。

## 代码入口

- [areas_page.dart](../../../../apps/pure_live/lib/features/areas/areas_page.dart)
- [tv_areas_pane.dart](../../../../apps/pure_live/lib/tv/pages/tv_areas_pane.dart)

## 当前进度

5.4.17冻结范围后到达，仅评估登记并回复，保持issue开放；没有计入本版已修复，也尚未完成原机验收。
