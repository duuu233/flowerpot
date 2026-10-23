# OTA 中断后接回：关 App 重开、息屏、断网恢复

> 文档类型：Historical Change Record
> 日期：2026-10-23；环境：远程 SSH 服务器
> 分支与起始版本：main / 2c66572
> 依据：产品要求「OTA 中途关闭 App、手机息屏、网络中断，恢复后需要继续 OTA」；当前契约见 [OTA 实现说明](../other/OTA_实现说明.md) 文首

## 核查结论（改前）

- Android：点升级入口能接回 SDK 已有任务（2/5 只挂监听）；但「其他设置」/设备页静默检查查到升级中只记标记不挂接，那一行不显示百分比；断网时 SDK 若先报超时/失败，原生释放监听、停止查询，恢复后百分比不再走（有进度的转核验，准备阶段的直接失败），需用户再点入口。
- iOS：`checkFirmware` / `startFirmwareUpgrade` 只认 `upgradeStatus == 1`，升级中被当成「当前已是最新固件版本」，无法接回；挂起期间回调丢失、无查询兜底，<98% 时完成会卡到 10 分钟停滞提示。

## 改动

1. iOS 识别升级中：`checkFirmware` 回 2/5 为 `inProgress` 并带 `componentType`；`startFirmwareUpgrade` 按目标版本/组件筛选，仅 2/5 时只挂 delegate 并回 running，不重新下发。
2. 进页面自动接回：`FlowerpotState.checkFirmware` 查到 `inProgress` 且本地没有在走的任务（无、失败、核验中、停滞）即 `_reattachOta`；设备页提醒、花盆「其他设置」静默检查、升级入口共用。`runFirmwareUpgrade` 升级中分支直接开进度。`_rememberFirmwareUpdate` 同版本由待装变升级中也更新。
3. 回前台 / 网络恢复接回：`resumeDeviceWatch` 立即、前台在线轮询每台最多 30 秒一次，对 SDK 非明确失败 30 分钟内、核验中、停滞（iOS 回前台另含所有进行中）重新问 SDK，仍在升级就接回，同目标保留百分比。
4. SDK 已无任务时转核验：回来后 SDK 无可升级固件，在等结果的这次转核验并现读设备版本，对上目标即完成。
- 测试：`state_ota_recovery_test.dart` 新增 7 例（静默检查接回且不重复、超时后回前台接回保留百分比、准备阶段失败接回、明确拒绝不接回、超 30 分钟不接回、iOS 回前台版本核验成功、Android 正常进行不重挂）。

## 决策

- 网络恢复不新增 connectivity 依赖（项目既有决定），借前台在线轮询节流重试。
- 接回窗口 30 分钟、节流 30 秒为本轮自定，不是 SDK 约束。
- 永不重新下发：只有 SDK 报 2/5 才接回，原生对 2/5 只挂监听。

## 验证

本机无 Flutter/Dart、无 Mac：测试、分析、格式化、Kotlin 与 iOS 编译均未运行；人工逐行核对调用点与既有用例（原「已有任务恢复」用例在静默检查即接回后仍成立）。未真机。

## 待确认与回滚

- 真机核对：App 被杀重开时 SDK 是否返回 2/5；断网时 SDK 是否先报超时；iOS 新 delegate 是否继续收到进行中任务的进度；iOS `ThingSmartFirmwareUpgradeModel.type/version` 类型与比较能否编译。
- 回滚撤销本提交即可，无数据迁移。
