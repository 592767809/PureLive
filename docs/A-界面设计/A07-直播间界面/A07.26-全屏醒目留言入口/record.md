# A07.26 记录

2026-10-23，分支 ai/V02.21，基于 da1e678d7072807aa59a9de4f5e9f91f106cd7c3。

## 实现

全屏和电视增加活动 SC 入口与默认开启的 showFullscreenSuperChat 设置。复用 RoomSuperChatPanel/SuperChatList 和现有最多 500 条会话历史；过期隐藏入口，已打开的历史仍可查看。电视面板由页面管理返回与焦点，上下滚动不换台。

## 回归

新增 3 条本任务回归，见 live_play_room_test.dart、tv_test.dart。改前失败日志：sc-ipad-before.log、tv-sc-before.log；改后定向测试通过。日志保存在本机 outputs/purelive-issues-20261023-batch2；没有把编译失败或测试夹具错误算作缺陷证据。

合计新增 13 条：静音 2、电视首选平台 1、SC 3、iPad 手势 1、常亮恢复 3、取流诊断 3。选定回归含旧 #12/#14，结果与全量门禁分别保留。可选 Widget 截图使用合成数据，不是真机视频或验收。

## 停在哪

实现与定向回归完成，未发布；真机步骤见 verify.md。推送前必须运行完整门禁，提交后 Apple 原生编译和模拟器启动结果附在 PR 与本机回执；此记录不预先声称通过。未操作正式安装、原始 Claude 目录或用户账号。
