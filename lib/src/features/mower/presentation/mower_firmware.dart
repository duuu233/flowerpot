import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_repository.dart' show TuyaException;
import '../../devices/presentation/device_online_guard.dart';
import '../../devices/presentation/device_other_settings_page.dart';
import '../../devices/presentation/widgets/ota_progress_dialog.dart';
import '../mower_dp.dart';

/// 割草机「设备升级」（2026-09-23 联调：「设备 OTA 还没有对接」）。
///
/// OTA 不是功能点，和花盆同一套：涂鸦 SDK 的 OTA 接口（Android `newOTAInstance` /
/// `getOtaInfo` / `startOta`），经 [FlowerpotState.checkFirmware] /
/// [FlowerpotState.upgradeFirmware]，进度与成败从事件通道回来（[showOtaProgressDialog]）。
/// 确认框、进度弹层都用花盆那两个。
///
/// 协议 V2.3 §7.2 的 DP116 `ota_status` 是设备侧的补充上报（"7" 非待机拒绝升级 /
/// "20" 升级失败），由 `MowerDevice` 收到后经 `failures` 弹提示；⚠️ 设备**不在待机**时
/// 会拒绝升级，所以升级前先提醒一句。
///
/// [confirmed] 为 true 时跳过「检查更新」确认框：用户已经在固件升级提醒弹窗里点过
/// 「立刻更新」（`FirmwareReminderHost`，与花盆同口径）。已经知道新版本（红点那次查到的）
/// 就不再问第二遍涂鸦。
Future<void> upgradeMowerFirmware(
  BuildContext context,
  String deviceId, {
  bool confirmed = false,
}) async {
  final state = FlowerpotScope.of(context);
  final device = state.deviceById(deviceId);
  if (device == null) return;
  if (!device.online) {
    showAppMessage(context, '割草机已离线，无法检查固件', tone: AppMessageTone.info);
    return;
  }
  final progress = state.otaProgressFor(deviceId);
  if (progress?.status == OtaStatus.running && !state.otaStalled(deviceId)) {
    await showOtaProgressDialog(context, deviceId: deviceId);
    return;
  }
  if (progress?.status == OtaStatus.running) state.clearOtaProgress(deviceId);

  state.logMowerInteraction('固件 → 割草机 $deviceId 检查新版本（涂鸦 OTA，非 DP）');
  FirmwareUpdate? update = state.availableFirmwareFor(deviceId);
  try {
    update ??= await withBlockingProgress<FirmwareUpdate?>(
      context,
      () => state.checkFirmware(deviceId),
    );
  } on TuyaException catch (error) {
    state.logMowerInteraction('固件 ✗ 检查失败：${error.code} ${error.message}');
    if (context.mounted) {
      showAppMessage(
        context,
        '固件检查失败：${error.message}',
        tone: AppMessageTone.error,
      );
    }
    return;
  } catch (error) {
    state.logMowerInteraction('固件 ✗ 检查失败：$error');
    if (context.mounted) {
      showAppMessage(context, '固件检查失败：$error', tone: AppMessageTone.error);
    }
    return;
  }
  if (!context.mounted) return;
  final currentVersion = update?.currentVersion ?? device.firmwareVersion;
  state.logMowerInteraction(
    '固件 ← 当前 $currentVersion，可升级 ${update?.version ?? '无'}'
    '${update == null ? '' : '（升级方式 ${update.upgradeType.name}）'}',
  );
  if (update == null || update.version == currentVersion) {
    showAppMessage(context, '当前已是最新固件版本');
    return;
  }
  if (!confirmed) {
    final accepted = await showFirmwareUpdateDialog(
      context,
      currentVersion: currentVersion,
      availableVersion: update.version,
    );
    if (!accepted || !context.mounted) return;
  }
  final result = await state.upgradeFirmware(deviceId, update.version);
  state.logMowerInteraction(
    result.success
        ? '固件 → 已发起升级到 ${update.version}（设备不在待机会拒绝，看 DP${MowerDp.otaStatus}）'
        : '固件 ✗ 发起失败：${result.message}',
  );
  if (!context.mounted) return;
  if (!result.success) {
    showDeviceActionResult(context, result);
    return;
  }
  await showOtaProgressDialog(context, deviceId: deviceId);
}
