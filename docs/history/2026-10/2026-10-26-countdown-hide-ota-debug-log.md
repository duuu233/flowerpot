# 倒计时隐藏规则、DP119 等待转圈、OTA 提醒门禁与 OTA 调试日志文件

> 文档类型：Historical Change Record
> 日期：2026-10-26；环境：远程 SSH 服务器
> 分支与起始版本：main / e29a8f1

## 依据与范围

用户五点要求：1）倒计时为 0 隐藏；2）APP 下发 DP119 后直接显示倒计时、时间处 loading，等 DP121 上报后显示；3）隐藏只依赖 DP121 算出的倒计时为 0；4）设置页下方有弹出层在执行 OTA 时，所有 OTA 提醒弹窗都不显示；5）OTA 完整 Debug 日志保存到手机文件，精确定位反复出现的失败。产品说明：`docs/reports/2026-10-26-割草机倒计时与OTA改动说明.md`（同日合并）。

## 改动

倒计时：
- `MowerDevice.visibleWorkEndsAt` 只看 `workEndsAt` 是否晚于当前时刻，去掉 DP5 待机/休眠、DP113、在线条件。
- 新增 `awaitingWorkPlan` / `workPlanWait`（60s）：`setOperatingTime` 下发成功后进入等待，记下当时的 `currentPlan`；收到身份（st/et）不同的 DP121（含无计划）或到点结束；解绑 / 重置时清掉。
- `MowerStatusCard.workLoading`：等待时图标 + 10px 转圈（`mower-work-countdown-loading`）；`_WorkCountdown` 减到 0 返回空，连同前面的间距一起收起。

OTA 提醒门禁：
- 新增 `OtaProgressLayer`（`lib/src/tuya/ota_progress_layer.dart`），进度弹层 init/dispose 计数。
- `FirmwareReminderHost` 监听它，开着时评估前后都直接返回；`MowerDevice` DP116 提示在该设备进度层开着时不进 `failures`。

OTA 调试日志：
- 新增 `OtaDebugLog`（`lib/src/core/logging/ota_debug_log.dart`）：按天追加文件、串行写、保留 7 天、内存保留最近 2000 行；总闸 `DebugLogGate.enabled`，`flutter test` 下默认不写。
- Dart 钩子：`MethodChannelTuyaRepository._otaUpdate`（原生 `otaLog` 事件与原样 OTA 事件）、`FlowerpotState`（检查固件、发起 / 返回 / 报错、进度合并前后与终态忽略、清除、核验现读、版本 DP 与 DP116、割草机充电前置、前后台、`[ota-timing]`、所有「OTA」开头的联调日志）、进度弹层（显示内容变化、开 / 关）、升级提醒（弹出、用户选择）、`runFirmwareUpgrade`（入口状态、各分支、用户选择）。
- Android：`otaLog`（受 `BuildConfig.APP_DEBUG_TOOLS`）+ `otaBean` dump；checkFirmware 列表 / 失败、发起参数与路径、服务回调和轮询快照原始 bean（含被忽略的原因）、升级信息列表与匹配 / canUpgrade / remind、调用与返回、异常根因、终态回调（含是否本次尝试）、轮询失败、实例释放；`TuyaOtaListenerBridge` 增可选 `trace` 记录旧版监听原始回调。
- iOS：`otaLog` 事件（由 Dart 总闸丢弃用户包）；checkFirmware / getFirmwareUpgradeInfo 模型列表、匹配结果、upgradeFirmware 受理 / 失败（NSError domain/code/描述/userInfo）、delegate 进度 / 成功 / 失败、实例释放；Info.plist 开 `UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace`。
- 联调日志框新增「OTA日志」：复制本次运行日志并提示文件路径。
- `pubspec.yaml` 新增 `path_provider: ^2.1.4`；**pubspec.lock 未更新**（本机无 Flutter），需在有工具链的环境 `flutter pub get` 后一并提交。

测试：
- `mower_work_countdown_test`：减到 0 收起、等待转圈优先于时间、DP119 后无计划兜底帧不结束等待 / 新计划结束、60 秒到点结束、离线发送失败不转圈、隐藏只看剩余（各 DP5 状态与离线均显示）。
- 新增 `test/core/ota_debug_log_test.dart`（文件格式、脱敏、7 天清理、总闸关闭、目录不可用、进度层计数）；`firmware_reminder_test` 增「进度层开着不弹、关掉后弹」。

## 验证

本机无 Flutter / Dart / Android SDK / Xcode：Dart 测试、静态分析、格式化、Kotlin 与 Swift 编译均未运行；未真机。`git diff --check` 通过。Swift 中未确定存在的模型字段（desc）已不使用。

## 剩余 / 风险

- 需在有工具链的环境：`flutter pub get`（更新 lock）、`flutter analyze`、`flutter test`、Android / iOS 各编译一次。
- iOS 开文件共享后，文档目录在正式包里也会出现在「文件」App（目前只有 OTA 日志写这里，正式包不写；若第三方 SDK 往文档目录写文件也会可见）。
- Android 11+ 系统文件管理器通常看不到 `Android/data`，需 USB / adb 或「OTA日志」复制。

## 回滚

还原对应提交；删除 path_provider 依赖与 Info.plist 两个键即可恢复原状。
