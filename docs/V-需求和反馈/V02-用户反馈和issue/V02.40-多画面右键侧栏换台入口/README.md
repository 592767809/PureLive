# V02.40 多画面右键侧栏换台入口

来源：[GitHub #43](https://github.com/wzgrx/PureLive/issues/43)。Windows 用户希望沉浸和全屏模式右键侧栏增加换台选项。

## 当前证据

`apps/pure_live/lib/features/multiview/widgets/cell_view.dart` 将右键映射到页面长按处理；`multiview_page.dart` 的 `_onCellLongPress` 在沉浸和全屏打开 `_Overlay.cell`，侧栏复用 `_controls(compact: true)`；`cell_controls.dart` 的同一组图标包含 `multiview-control-change`，回调 `_openPicker(index)` 记录当前格并切换到选台面板。已存在的换台和侧栏回归由 5.4.13 完整门禁覆盖，不将代码接线等同于原 Windows 实际界面验收。

## 处理

已回复图标入口与鼠标提示，要求补充完整版本、Windows 缩放和侧栏截图，并区分“入口缺失”与“希望明确文字菜单”。保持 issue 开放。当前发布没有改动多画面行为，也没有声称本需求已实现。

## 下一步

收到原环境信息后先复现。若入口未显示，按实际原因修复；若只是文字可发现性需求，先按 PROCESS 界面流程评估并形成方案，再开实现任务。不得仅凭本记录关闭 #43。
