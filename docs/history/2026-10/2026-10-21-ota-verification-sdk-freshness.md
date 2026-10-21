# OTA 报错后结果核验扩展与 SDK 值去缓存

> 文档类型：Historical Change Record
> 日期：2026-10-21；环境：远程 SSH 服务器；分支与起始版本：main/2cbf14a
> 当前权威文档：PRODUCT_RULES.md §4.14/§4.26、OTA_实现说明.md 文首、DEVICE_ONLINE_STATUS.md
> 简明说明：[reports/2026-10-21-OTA结果与SDK实时读取.md](../../reports/2026-10-21-OTA结果与SDK实时读取.md)

## 背景

用户反馈「OTA升级还是会失败，但是其实已经成功了」，并要求「所有读取涂鸦SDK的值的都做及时刷新，不延迟，不缓存」。干净工作区先 `git pull --ff-only origin main`（已最新）。本机没有 `.codegraph/`，也没有 flutter/dart/node/codegraph/Kotlin 工具链，只能读源码定位。

## 源码确认的原因

- `_applyOtaProgress` 只在前一状态 displayStage 为安装中时，才把 SDK 失败转成核验。96% 而无阶段6（iOS 不转发阶段码）的失败直接终态，晚到的目标版本无法纠正；`state_ota_confirmation_test` 中原有一条用例固定了这个行为。
- 核验只认本条 DP148/112 String 推送。`onDevInfoUpdate` 带来的 `verSw`、清单刷新、SDK 当前模型都不参与；App 也从不主动读设备当前版本。
- `runFirmwareUpgrade` 复用红点时缓存的 `availableFirmwareFor`；设备页提醒按 1 分钟节流；`productNameFor` 会话级缓存。
- `MethodChannelTuyaRepository.getDevices` 只要查询期间来过任一推送，就整台丢弃新清单、退回旧快照；状态层也有同样的整台丢弃。

## 变更

- OTA：已有升级进度（升级中/安装中/已在核验）后，非明确拒绝的 SDK 失败转 `verifyingVersion`；明确拒绝码集中为 `_definitiveOtaCodes`，Android 失败事件新增 `code`。核验中 `_confirmOtaByPendingReport` 不再要求安装阶段。新增 `TuyaRepository.firmwareVersions`（原生 `deviceSnapshot` 的版本DP + verSw），由 `_scheduleOtaProbe` 在进入安装/核验、设备推送、在线轮询、`refreshOtaResult` 时现读，单设备串行并补读一次。发起时记录版本基线 `_otaBaseline`，读基线失败（`_otaBaselineRead` 为 false）时不用现读值判定。进度弹层在核验中改为不定进度动画。
- 去缓存：升级入口每次 `checkFirmware`；`FirmwareReminderHost` 改按（设备页、设备、固件版本）重查，离开设备页或离线时清空；`productNameFor` 不跨页面缓存；`getDevices` 用 DP/在线序号只叠加查询期间到达的项（`_overlayNewer`），状态层只保护清单返回之后的推送；`onlinePollInterval` 8→3 秒，Android `OTA_POLL_INTERVAL_MS` 8→3 秒。
- 保留：准备阶段零进度失败直接失败、2 分钟「暂未确认」、DP116=7/20 优先、写入回显保护、消息 2 秒延迟拉取、家庭 ID 记忆；未改 iOS 原生、OTA 传输或依赖。
- 测试：调整 1 条旧口径用例，新增 OTA 核验 11 项、仓库逐项合并 3 项 + 状态层 1 项、SDK 版本现读 3 项、错误码 1 项、提醒重查 1 项；测试替身 `MockTuyaRepository` 增加 `firmwareVersions`。

## 验证

本机无工具链：**没有运行** flutter test、dart analyze、dart format、Android 编译。只做了人工代码走查：逐条核对既有 OTA、提醒、在线、清单相关用例在新规则下的预期；Kotlin 只改了常量和一个具名参数。CodeGraph 不存在，未同步。需要在有工具链的环境执行：

```bash
dart format lib test
dart analyze lib test
flutter test test/state_ota_confirmation_test.dart test/state_ota_test.dart test/state_ota_recovery_test.dart test/app/firmware_reminder_test.dart test/tuya/device_updates_test.dart test/state_reachability_test.dart test/features/devices/device_other_settings_page_test.dart
```

以及 Android `:app:compileDebugKotlin`。

## 风险与待验收

- 下载段真实失败（例如 30% 下载中断）现在会先显示「正在确认升级结果」，2 分钟后显示「暂未确认」，不再直接「升级失败」。这是为避免误报所做的取舍；如需更早判失败，要有设备/平台给出的失败依据。
- `verSw` 由 SDK 在设备重连后更新，具体时机以真机为准；多组件设备依赖版本基线排除巧合。
- 清单刷新与乐观设置：查询期间的本地乐观设置会被这次 SDK 新值替代，等设备回显后恢复。
- 真机验收步骤见简明说明第 4 节。

## 回滚

撤销本次提交即可恢复 10-20 规则和原有缓存/轮询间隔。不涉及后端数据、平台配置或固件。
