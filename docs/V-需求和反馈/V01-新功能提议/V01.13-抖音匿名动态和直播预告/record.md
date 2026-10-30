# record

2026-10-30：核对最新 master、全部开放 issue 和历史回复。用户已委托维护决策、开发、合并、发布与已验证 issue 收尾。

## 2026-10-30 第二实现检查点

抖音官网当前LiveReserveCard从RoomDataSyncMessage的HighlightContainerSyncData读取appointment_data.date_text/time_text；原生RoomIntroMessage还可携带独立公告和预约。已加会话内强类型更新和手机/桌面/电视信息栏；不把签名解析为预告，不写入历史备份。模型1、协议3、原协议联合66、应用元数据与控制联合10测试通过。匿名WebSocket连接采样成功，但该样本未返回预告，原生正例尚待补充；旧公告HTTP接口十次匿名返回20003，请登录，不作为可用匿名接口。

所有九项需求完成后统一发版。当前未跑最终全量门禁，未推送、未发布、未关闭issue。


### 2026-10-30 真实匿名正例与初始快照

从官方公开feed取得8间当前直播间，仅使用匿名ttwid会话和随机访客ID；按官方初始消息模式发起空cursor的`/webcast/im/fetch/`，得到protobuf消息响应。已从实际HighlightContainerSyncData解码出“每周日二三五六17:00”，多个RoomIntroMessage同时提供动态。原签名探测的空体不是“主播没有预告”；不能把此类失败清成已知无预告。

连接新增可选共享HTTP依赖，socket ready后异步取初始快照，继续正常实时消息。只发出roomInfo，不向聊天重放历史。8秒超时、2MiB限制、关闭取消、连接/广播/请求代际检查；元数据取不到不关闭弹幕。应用与CLI均注入原有HTTP/代理策略，默认无HTTP的原测试保持离线。

新增脱敏真实字段样本S14-room-information及两项回归，验证实际周循环显示、动态独立、空游标、跨房过滤、关闭取消/迟到响应、历史聊天不重放。连同原协议与连接测试共68项通过。完整原始响应、临时匿名请求头与Cookie仅在仓库外，样本只留所需协议字段及原件哈希。仍待候选应用中的原生展示验收。
