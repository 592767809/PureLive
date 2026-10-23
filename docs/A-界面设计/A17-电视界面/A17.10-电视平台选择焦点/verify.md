# A17.10 验证

## 自动验证

tv_preferred_platform_test.dart：新增 1 条，对应改前失败、改后通过。常亮测试包含请求丢失、第一次异常后重试、延迟开启后的最终关闭；iPad 手势为模拟通道；SC 检查真实命中与动画关闭，不仅检查组件存在。

## 真机待验

Sony KD-65X8566E / Android 9 / v7a：设置→平台显示与认证→首选直播平台，确认不弹键盘；方向键逐项走，OK 保存；重开检查当前项焦点，再选其他项后按 Back，设置值不变。手机入口保留筛选。

本轮没有执行物理设备操作。逐条记录设备、系统、提交、安装包哈希、输入方式和结果；待真机不等于已修复验收。任何发版要另走发布流程，不改本轮版本号与更新 JSON。

## 合成界面证据

以下为 Widget 测试，假播放、假房间、无真实平台数据；不是原生设备截图。改前画面只将对应生产入口文件还原到 da1e678d，使用相同夹具；截图后已校验恢复工作树指纹。用于核对入口、焦点、布局和列表，不能证明物理播放或遥控器兼容性。

![before-tv-preferred-platform](verify/before-tv-preferred-platform.png)

![tv-preferred-platform-focused](verify/tv-preferred-platform-focused.png)
