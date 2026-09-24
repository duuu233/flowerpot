import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../devices/presentation/firmware_upgrade_flow.dart';

/// 割草机「设备升级」：和花盆「固件版本更新」**同一个入口** [runFirmwareUpgrade]
/// （2026-09-24 用户：「按花盆的统一……能复用的就复用，包括逻辑和交互」）。这里只多接一条
/// 割草机联调日志。
///
/// 割草机独有的只剩设备侧上报：DP113 `fw_version` 是当前版本（与花盆 DP148 同用法，
/// 见 `TuyaRepository._device`）；DP116 `ota_status`（"7" 非待机拒绝升级 / "20" 升级失败）
/// 由 `MowerDevice` 收到后经 `failures` 弹提示。
Future<void> upgradeMowerFirmware(
  BuildContext context,
  String deviceId, {
  bool confirmed = false,
}) {
  final state = FlowerpotScope.of(context);
  return runFirmwareUpgrade(
    context,
    deviceId,
    confirmed: confirmed,
    log: state.logMowerInteraction,
  );
}
