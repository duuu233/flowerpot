# OTA「正在确认升级结果」最多 3 分钟出结论

> 文档类型：Historical Change Record
> 日期：2026-11-19；环境：远程 SSH 服务器
> 分支与起始版本：main / c1a8655

## 依据与范围

产品要求：App 显示「正在确认升级结果」后最多 3 分钟要出结果。原实现 2 分钟后只显示「暂未确认升级结果」（仍是进行中、不下结论）。

只管「正在确认」这一段（SDK 报失败 / 超时后的版本核验、回前台 SDK 已无任务的核验）；正常升级中的停滞保护（准备 2 分钟、其它 10 分钟）不变，整个升级过程不限时。

## 交互

- 0 ~ 3 分钟：「正在确认升级结果」，进度条动画，提示「通常 1~2 分钟内完成」；仍按 3 秒轮询等现读，读到目标版本立即「升级完成」；可关闭窗口。
- 满 3 分钟：最后现读一次 SDK 当前设备版本，按证据给结论：

| 到点时 | 结论 | 弹层按钮 |
| --- | --- | --- |
| 读到目标版本 | 升级完成 | 知道了 |
| 设备在线，读到的版本全是升级前的 | 升级失败：「设备当前仍为 Vx，本次升级未生效，可重新升级。」 | 知道了 / 重新升级（直接发起，不再弹确认框） |
| 离线、读不到版本或发起前没拿到版本基线 | 升级超时：「3 分钟内未收到设备确认，请检查设备电源和网络后重新检查。」 | 知道了 / 重新检查（重走入口、现问涂鸦） |

- 「其他设置」固件行显示「升级失败」/「升级超时」；弹层已关且用户停在该设备页时弹一条轻提示，不在该设备页不补弹。
- 收尾后 120 分钟内晚到的真实版本（版本 DP、SDK 现读、SDK 成功回调）仍静默转「升级完成」，更新版本号、熄红点，不另外弹窗。
- 再点升级入口：先丢掉这次结论再检查；SDK 报仍在升级时照常接回。收尾后不自动弹升级提醒。
- App 在后台跨过 3 分钟：回前台第一拍轮询就收尾。

## 改动

- `OtaStatus` 新增 `timedOut`；`FlowerpotState.otaVerificationTimeout` 2 → 3 分钟。
- `checkOtaVerificationDeadline` / `_concludeOtaVerification`：到点最后现读并收尾（失败带 code `verification_unchanged`，超时带 `verification_timeout`）；调用点为前台在线轮询、`refreshOtaResult`（重开入口）、进度弹层每秒刷新。未新增计时器。
- 收尾后保留目标与版本基线（`_otaLateTarget` / `_otaConcludedAt`），`_otaProbeWanted`、`_confirmOtaByReportedVersion`、`_applyOtaProgress`（SDK 成功）据此晚到转成功（`_resolveLateOta`）。
- `otaVerificationConcluded`、`takeOtaConclusionNotices` 供弹层、升级入口、升级提醒宿主使用。
- `showOtaProgressDialog` 返回 `OtaProgressAction?`（重新检查 / 重新升级）；`runFirmwareUpgrade` 收到后清掉本地结论重走一遍。
- 进度弹层：升级超时标题与橙色进度条、两按钮；核验中去掉「暂未确认升级结果」中间态。升级入口的「暂未确认升级结果」确认框去掉（核验中一律打开进度弹层）。
- `FirmwareReminderHost`：收尾轻提示；结论状态下不自动弹升级提醒。
- 用例：`state_ota_confirmation_test.dart` 截止时间改 3 分钟，新增超时 / 版本未变失败 / 到点读到目标 / 晚到成功 / 弹层重新检查与重新升级；`firmware_reminder_test.dart` 核验 3 分钟用例的断言放宽为核验中或已收尾。

## 风险

- 「设备在线且版本全是升级前的 → 失败」：若是 MCU 固件、Wi-Fi 模组升级期间一直在线且 3 分钟内 MCU 未装完，会先显示失败；装好后晚到的版本仍会转成功。若真机出现这种情况，可把这一类也改按「升级超时」处理（只改 `_concludeOtaVerification` 里 `unchanged` 的判定）。
- 3 分钟按前台 3 秒轮询 / 弹层每秒检查，实际出结论最多晚约 3 秒。

## 验证

未编译、未运行测试、未真机（服务器无 Flutter）。待本地 `flutter analyze`、`flutter test test/state_ota_confirmation_test.dart test/state_ota_recovery_test.dart test/state_ota_test.dart test/app/firmware_reminder_test.dart test/features/devices/device_other_settings_page_test.dart`；真机用调试包在 96% 左右断开设备网络，确认 3 分钟出「升级超时」、设备恢复后转「升级完成」。

## 回滚

还原本次提交即可，无数据迁移。
