# 记录

2026-10-28：重读5个开放issue和近期关闭反馈，master及工作区干净，无开放PR。官方mpv手册及GitHub源码研究；微博旧接口show_pc_live、新PC接口anchor/live和官方网页JS均匿名读取。媒体端实际探针而非文件名推测，结果留在本任务证据目录。上游示例含登录值，未采用其凭据，仅独立验证公开端点和公开媒体。


2026-10-28源码冻结前新增#90/#91及#49复验反馈。#90的边框来自IptvSourceCard.inUse，而非默认来源特殊状态；取消所有节目单卡的常驻选中描边，保留“使用中”标签和电视遥控器焦点。#91两处仍使用1920草稿字号21/17和20，低于统一电视正文/次要文本；换成TvTextSize.body/small并增加列表行高。

#49报告清数据可播放、跨平台切换后所有源黑屏，新日志仍出现firstFrame和后续stall。已检查hwdec/http-proxy/audio-files/demuxer-lavf-format逐次重设以及media_kit卸载清HTTP头；未发现足以证明原机根因的持久化污染。上游mpv-android#613存在旧MediaCodec切源Surface失败，但原报告缺该原生证据，不能直接套用。确认一个诊断缺口：NativeBufferingProbe只debugPrint，而AppLog.install将其降为debug并在默认info过滤，导致导出日志缺缓存/解码状态。通过可注入的专用回调以playback/info记录其固定数字/布尔键，不降低日志隐私约束、不打印URL或原生全日志、不改变恢复和硬解策略。此修复仅补足诊断，#49继续开放。
