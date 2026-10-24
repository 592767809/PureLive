# Z02.5 macOS 精确候选的渲染后端对照诊断

原产品源 b1dea4c60418834430e0860147b953b446dcb19d 通过完整 14 成员门禁，但首轮 Mac 首页存在文字/图标像素缺损；精确 ZIP 的 SHA、CRC 和字体表边界/字形数量正常。一次同源独立 Mac-only 构建的首图仍是启动动画，随后菜单和重开为黑屏，也不接受。停止靠重建挑绿。

诊断分支 ai/Z02.5 暂时替换既有 Apple 工作流，下载源运行 40083139304 的精确 ZIP，核对源提交与 c8dca334c2ce68bbae5e66c910f45cc14b4016d0bf0489501daccc3e951205eb。两个副本去除签名后的代码副本哈希相同（Info.plist 的哈希会进入嵌入签名，所以不错误比较重签后的整文件），保持相同权限和签名处理，仅对 B 副本设置 FLTEnableImpeller=false。按预先固定的 A-B-A-B 顺序各启动两次，每次 5/30/60/90 秒截图并收集进程、标准输出/错误和统一日志。没有构建或发布正式包，结果不能未经逐图审查当作通过。

[Flutter 的 macOS 后端开关说明](https://github.com/flutter/flutter/blob/master/engine/src/flutter/impeller/README.md) 说明此键可退出默认 Impeller；它仅是对照变量的依据，当前尚未证明渲染后端就是根因。诊断分支工作流须经完整 all/14 门禁后推送，使用已登记的同名 Apple workflow 在分支运行，主分支工作流保持原样。后续若需产品修正，恢复原构建工作流，重新冻结产品源、跑全量门禁并构建同提交十包。

只处理隔离云端作业自己的进程和临时 bundle；下载令牌只在下载步骤可用，不向应用传递，不采集用户账号、Cookie 或本机数据。四次启动固定有界，不无限重试；失败候选、日志、图片、哈希全部保留。K90 当前等待维护者再次解锁后收尾，原数据、自动界面与精确旋转仍须恢复。


## 首次诊断脚本格式修正

运行 [40087495596](https://github.com/wzgrx/PureLive/actions/runs/40087495596) 已校验原构建和 ZIP SHA，但在权限导出后的 plist 校验退出，未启动任何 A/B 样本。macOS 的 codesign 默认输出抽象文本；按 [Apple TN3125](https://developer.apple.com/documentation/Technotes/tn3125-inside-code-signing-provisioning-profiles) 显式加 `--xml` 导出，再做 plist 校验。原失败日志、权限诊断与身份回执单独保留，不能计作渲染实验结果。应用、依赖和正式包均未修改；修正后仍须完整门禁再推送。


## 增加未改动原包控制

查阅 Y01.22 的已发布记录发现，重签名也可能改变启动表现，旧实验缺少同机未改原包控制。因此在修正后的实验推送前停止本轮本地门禁，并保留中断记录；实验固定为 `original-1 → default-1 → skia-1 → original-2 → default-2 → skia-2`。original 使用精确 ZIP 解出的未改包，default/skia 两组对称重签，仅后者额外禁用 Impeller。每次记录 5/30/60/90 秒画面及进程状态，30 秒采样；原包签名与主程序摘要在实验前后核对。若三组都正常或都失败，仍不能认定后端原因。产品源码未动，重新跑完整门禁再推送。
