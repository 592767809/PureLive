# A11.9 记录

2026-10-26：V03.8 重新审查，确认 `_focusFirst` 在非当前路由时直接返回且没有恢复触发。新增 `tv_settings_focus_lifecycle_test.dart` 在修改前失败：关闭对话框后 first.hasFocus 仍为 false。实现改为在 didChangeDependencies 订阅 ModalRoute.isCurrentOf，路由恢复时继续首次聚焦；增加回调去重，保留 `_focusedInitially` 防止已完成后的焦点抢占。回归和最终原生操作尚待完成。

## 定向验证

修改前真实Navigator+Dialog+延迟内容回归失败。修改后对话框覆盖时不抢焦点，关闭后首个可用行获焦；用户选择第二行后再次开关对话框，仍保留第二行。相关房间与电视设置110项通过，原机操作单独记录。

最终完整 all/14、跨平台最终源码包与原生验收正在继续；本记录不替代那些检查。
