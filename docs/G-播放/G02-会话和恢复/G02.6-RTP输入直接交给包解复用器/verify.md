# G02.6 RTP输入直接交给包解复用器

首轮5.4.15候选 `2abd6610c53ffd7582e75f0412aee4a189ae6b0f` 完整all/14及六个本地正式包通过，但Linux真实RTP测试停在缓冲，不能据协议白名单宣称已支持播放。所有首轮包、回执及失败图片已保留在本地独立 candidate-1 目录，未公开发布。

本地发送包为RTP v2、静态payload33，头后为MPEG-TS；独立FFprobe对原URL及显式本地端口URL均识别H.264/AAC，因此“必须显式本地端口”假设已被排除。精确候选libmpv默认路径将原始数据报交给字节探测，未识别有效视频；强制rtp格式在单播样本中遇重复绑定。mpv的opaque `av://rtp:<原rtp地址>` 直接使用FFmpeg RTP解复用器，受控对照已识别320像素视频及时间位置。原生应用持续变化画面仍需随后预检，不把这一步识别写成完整播放器验收。

官方对应修复：[mpv 4fdd1d4662](https://github.com/mpv-player/mpv/commit/4fdd1d4662)、[原报告18115](https://github.com/mpv-player/mpv/issues/18115)。本项目不复制C实现、不替换二进制内核，仅在MpvEngine打开RTP时映射内部输入，保留原媒体地址、端口、查询参数、重连和录制数据；其他协议使用原字符串，不改全局解复用选项，不影响后续HTTP／RTSP打开。

media_kit仅为这个内部RTP语法增加早返回，在Android content URI解析前保留opaque输入，避免把原媒体地址写进格式异常日志。四个组播、单播、参数与IPv6回归在原输入行为下失败，修正后连同六个其他协议对照全部通过；同时覆盖Media的实际标准化边界。测试不访问平台。

允许范围：packages/live_player 的 mpv_input.dart、mpv_engine.dart及对应测试，third_party/media_kit 的 media_native.dart精确内部RTP前置识别，本任务与发布文档。不得把RTP改写成UDP，不丢地址或查询参数，不改其他协议或全局mpv选项，不读用户数据库或正式安装。

步骤：保留原生失败和旧候选；原输入行为先跑失败回归，再启用RTP专用入口；Linux profile预检实际接收变化画面及节目单，之后完整all/14并由新提交重新构建十个包，核对远端哈希、各端启动和K90同源包。旧候选不混入新清单，原运营商网络仍有现场边界。

当前尚未发布，新候选原生结果与完整门禁后续记录。


## 实际profile接入补充

首次profile预检确认独立libmpv直开正常并不够：media_kit默认先写播放列表再loadlist，内部av RTP语法被播放列表协议策略拒绝，画面中断。现在仅fd与精确内部RTP入口走逐文件loadfile；其他av输入不放开，HTTP、RTSP、UDP仍走原路径。四项RTP加载策略回归在旧fd-only策略下失败，连同原归一化、描述符与任意av拒绝对照共12项修正后通过；失败profile与截图保留。允许范围补充native/core/direct_media_load.dart、native/player/real.dart及对应测试。后续仍须原生画面预检和新提交完整门禁、十包。


## Linux profile原生预检结果

接入逐文件路径后，使用原单播RTP地址和同一生成的视频，实际计数345→391、时间23.000→26.067秒，画面持续变化，首屏节目单出现。启动时出现一次video_decoder_runtime自动恢复，随后result=playing，后续画面持续变化且无新增恢复；未将这次容器测试写成零恢复、硬件解码或听感验收。该预检为profile、静音、回环网络，不是正式包或运营商现场验收。完整源指纹与截图哈希在独立回执中保留。

预检后仅补Android专用finalizer的fd前缀判断，避免对内部opaque RTP地址做Uri解析并打印格式异常；Linux的RTP输入、逐文件加载实现未改。此Android分支将在最终同源K90包中检查；最终提交仍需完整all/14及十包、正式Linux原生重验。未把profile源指纹替换成最终源指纹，两者及这一行Android差异分别记录。
