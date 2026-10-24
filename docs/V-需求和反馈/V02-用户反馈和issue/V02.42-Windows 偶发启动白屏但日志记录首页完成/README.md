# V02.42 Windows 偶发启动白屏但日志记录首页完成

构建期间新增并有第二用户反馈。原 Win10/GTX760/475.14 从托盘退出，白屏时拖动及隐藏恢复无效，但盲点最大化后主页出现，再还原正常。首帧338ms、首页1323ms和尺寸变化恢复使首次呈现时序成为线索，尚不能断言根因；隔离候选三次正常不代替原机修复验收。

来源：[#47](https://github.com/wzgrx/PureLive/issues/47)。保留开放，未作修复发布声明。


最新原图已查看：整个客户端区和自绘标题栏均白，但按钮仍能盲点；最小化／恢复同样无效，盲点最大化可恢复，再还原保持正常。[补图](https://github.com/wzgrx/PureLive/issues/47#issuecomment-6387083306)、[回复](https://github.com/wzgrx/PureLive/issues/47#issuecomment-6387361866)。呈现／窗口尺寸时序仍是待验证假设。
