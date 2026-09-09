# OTA 弹窗里两个版本号都不对

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：SSH
> 分支与起始版本：main / b7b6ad6
> 范围：Android / iOS 桥接的固件字段与 `checkFirmware`、`TuyaRepository`、`FlowerpotState`、其他设置页
> 当前权威文档：`AI_CONTEXT.md`、`docs/TUYA_SDK_SETUP.md`

## 背景与目标

反馈：「固件版本更新」弹窗里的**当前版本**和**发现新版本**都读错了，怀疑是上次加 OTA 进度弹层改坏的。

## 排查结论：不是进度弹层改坏的

`992b8f8`（2026-09-08，加进度弹层）对这条路径只改了一处——升级发起成功后，把原来的一条 toast 换成 `showOtaProgressDialog`。取版本、比版本、弹「检查更新」框的代码一行未动（`git show 992b8f8 -- device_other_settings_page.dart` 可复核）。两个版本号的读法分别来自：

- 弹窗的「当前版本」= `device.firmwareVersion`，源头是 Android 桥接 `deviceMap` 里的 `"firmwareVersion" to (getPv() ?: getVersion())`——**`DeviceBean.getPv()` 是通信协议版本**（`2.2` 这种），不是固件版本；固件版本在 `verSw` 上。这行是 2026-08-12 `b0c773f` 就有的。iOS 的 `deviceMap` 干脆没有这个字段，只能退回 DP 148 或 `--`。
- 弹窗的「发现新版本」= `getOtaInfo` 里 `upgradeStatus == 1` 那条的 `getVersion()`。字段本身没错，但它是**某个可升级组件**（MCU / Wi-Fi 模块）的版本号，和上面那行根本不是同一个来源；设备有多个组件时两行必然对不上。

也就是说：弹窗第一行显示的是协议号，第二行是另一个组件的新版本号，看起来就是「两个都错」。这套显示（`showFirmwareUpdateDialog`）从 2026-07-20 `bdd9c29` 起就是这样，进度弹层只是让用户更常打开它。

## 变更内容

- **Android `deviceMap`**：`firmwareVersion` 改取 `getVerSw()`，取不到再退 `getVersion()`，不再用 `getPv()`。
- **iOS `deviceMap`**：补上 `"firmwareVersion": device.verSw`，与 Android 对齐（之前根本没这个键）。
- **两端 `checkFirmware`**：从只回一个版本号字符串，改为回 `{version, currentVersion}`——两个版本号取自**同一条 OTA 记录**（Android `getVersion` / `getCurrentVersion`，iOS `pending.version` / `pending.currentVersion`）。
- **Dart**：新增 `FirmwareUpdate{version, currentVersion}`；`TuyaRepository.checkFirmware` 返回它，解码时兼容旧原生包只回字符串的情况；`FlowerpotState._availableFirmware` 改存这个模型，`_rememberFirmwareUpdate` 比较的基准优先用 OTA 记录里的当前版本、取不到才退回设备列表的固件版本。
- **其他设置页**：弹窗的「当前版本」优先用 `update.currentVersion`，没有才退回 `device.firmwareVersion`；「已是最新」的判断也改用同一对版本号。

## 关键决策

- 没有把「当前版本」直接换成 DP 148（`firmware_version`）：DP 只有设备上报了才有，而 OTA 记录里的 `currentVersion` 与待升级组件严格对应，用它做主、设备字段兜底最稳。
- 解码保留对「旧原生只回字符串」的兼容：手机上装着旧包、只更新了 Dart 层时不至于整块功能失效。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK，也没有 Android SDK 与 Xcode**：`flutter analyze`、`flutter test` 未执行，两端桥接改动**未编译**。
- 新增/调整用例（未运行）：`state_ota_test.dart` 增加「SDK 报的当前版本压过设备列表里的固件版本」「SDK 把当前版本原样回来时不算新版本」两例并改用 `FirmwareUpdate`；`device_other_settings_page_test.dart` 增加「弹窗的两个版本来自同一条 OTA 记录」，原有断言（`V1.0.0` ×2、`V1.1.2`）在 `currentVersion` 为 null 时仍成立。

## 未完成项与风险

- **iOS 的 `ThingSmartFirmwareUpgradeModel.currentVersion` 需要在能编译的机器上确认字段名**；若该版本 SDK 没有这个属性，编译会报错，去掉那一项即可（Dart 侧对缺失值已做兜底）。
- 真机未验证：需要一台确实有新固件的设备，确认弹窗两行分别是「设备当前固件」和「待装版本」，且升级完成后设备信息页的固件版本随之更新。
- 改 `verSw` 之后，设备信息页「固件版本」一行显示的内容也会跟着变（原来同样是协议号），这是同一个根因的连带修正。
