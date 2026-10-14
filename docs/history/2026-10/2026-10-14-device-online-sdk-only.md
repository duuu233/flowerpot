# 设备在线状态只使用涂鸦 SDK

> 文档类型：Historical Change Record
> 日期：2026-10-14
> 环境：公司电脑 work
> 分支与起始版本：main / 674e0dd
> 范围：状态层、设备列表、Repository 与 Android/iOS 原生桥接
> 当前权威文档：[设备在线状态](../../DEVICE_ONLINE_STATUS.md)、产品规则 §4.8.1

## 背景与目标

用户要求花盆和割草机列表在线状态完全依赖涂鸦。新一轮开始前先同步当前 main 并刷新 CodeGraph。检查发现本地连续探测超时离线覆盖、Android 将网络可用值写入 online、DP113 列表优先级，以及 SDK 查询后 DP 缓存仍有旧 online。

## 变更与外部核对

- 状态层删除探测调度、计数和不可达集合，devices/deviceById 直接给 SDK 快照；命令通道选择也删除探测覆盖。
- 列表只读 online 显示在线/离线，DP113 控制页提示、安全门禁和下发保护保留。
- Android 仅设备状态回调改 online；网络状态回调不再混用。iOS 接 online delegate 与 SDK 状态读取，两者直接转发模型值。
- Repository 更新 SDK 查询后的 DP 合并缓存；新 SDK 快照优先于旧查询，旧登录会话查询丢弃。没有根据手机网络或收到 DP 推定状态。
- 官方 API 契约与引用在当前文档。没有调用真实业务接口、下发设备命令、升级依赖/SDK、修改签名或部署。

## 验证

- 120 项 Flutter 相关回归全部通过，覆盖列表 SDK true/false 与 DP113、超时不改 online、SDK 查询失败/空返回、实时推送、缓存一致性、查询竞争、登录会话隔离、控制关机、割草计划和固件提醒。
- 提取本次实际 `devListenerProxy` 并隔离编译执行：9 项原生回调行为检查通过，网络回调不产生 online、设备状态/DP/快照/移除正常。
- Android `:app:compileDebugKotlin -Ptarget-platform=android-arm64 --offline` BUILD SUCCESSFUL（2 分 5 秒），使用实际涂鸦 SDK；既有 Kotlin/Wi-Fi/资源格式/namespace/Gradle 警告保留。未生成安装包。
- 六个本轮 Dart 文件 analyze 无新增诊断；保留 state 的 unused_element 与 repository 的 unintended_html_in_doc_comment 两个既有提示。源码格式化后还原无关纪念日等格式差异。
- 前一轮已记录的全库旧失败不重复运行；本轮适用回归通过后，未宣称全库测试通过。
- Windows 无 Xcode，iOS 新桥接尚未编译；双端真机在线/离线及后台回来场景待按当前契约验收。

## 交接与回滚

只使用最新 SDK 设备在线值，设备云端心跳判定的等待时间由涂鸦决定。本轮没有补齐 iOS 独立 deviceLinkState，能力缺口继续留在原跟踪文档。需要回滚时撤销本次提交并同步本机 CodeGraph；本轮起始工作区干净，原始输入资料备份不随提交交付。
