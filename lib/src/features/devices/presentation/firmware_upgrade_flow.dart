import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../core/logging/ota_debug_log.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';
import '../../../tuya/tuya_repository.dart' show TuyaException;
import 'device_online_guard.dart';
import 'widgets/ota_progress_dialog.dart';

/// 固件升级入口：花盆「其他设置 → 固件版本更新」和割草机「设置 → 设备升级」**共用这一份**，
/// 固件升级提醒弹窗点「立刻更新」跳到这两页之后走的也是它（2026-09-24 用户：「能复用的就
/// 复用，包括逻辑和交互」）。
///
/// 依次：
/// 1. **正在升级**：没卡住就重新打开进度弹层；卡住了（[FlowerpotState.otaStalled]）弹
///    「升级似乎已中断」，确认后丢掉本地进度、重新问涂鸦（不再用红点那次的旧结论）。
///    放在离线判断之前：升级中设备重启、短暂离线是常态，这时要看的是进度。
/// 2. **离线**：提示「花盆 / 割草机已离线，无法检查固件」，不跳页。
/// 3. 每次都现问涂鸦有没有新版本（不拿红点那次的旧结论，2026-10-21 用户：SDK 的值
///    不缓存），没有就提示已是最新。
/// 4. 弹「检查更新」确认框（当前版本 → 新版本）；[confirmed] 为 true 时跳过。
/// 5. 发起升级：`startOta` 只代表「已发起」，之后的进度和成败从事件通道回来，
///    这里盖上进度弹层。
///
/// 问云端和发起升级期间，入口那一行转圈（[FlowerpotState.isCheckingFirmware]），
/// 同时挡住连点。[log] 给割草机的联调日志用，花盆不传。
Future<void> runFirmwareUpgrade(
  BuildContext context,
  String deviceId, {
  bool confirmed = false,
  void Function(String line)? log,
}) async {
  final state = FlowerpotScope.of(context);
  // 每一步同时写进 OTA 调试文件；割草机另外进联调日志。
  void note(String line) {
    log?.call(line);
    OtaDebugLog.ui(line, deviceId: deviceId);
  }

  if (state.isCheckingFirmware(deviceId)) return;
  final device = state.deviceById(deviceId);
  if (device == null) return;
  final local = state.otaProgressFor(deviceId);
  final localText = local == null
      ? '无'
      : '${local.status.name} ${local.displayStage.name} ${local.percent ?? '-'}% '
            'verifying=${local.verifyingVersion} stalled=${state.otaStalled(deviceId)}';
  note('固件 · 进入升级入口，本地进度 $localText，online=${state.isDeviceOnline(deviceId)}');

  if (state.otaProgressFor(deviceId)?.status == OtaStatus.running) {
    // 重新打开进度时先现读一次 SDK 当前版本：设备可能已经装好，只是结果还没推上来。
    state.refreshOtaResult(deviceId);
    if (!state.otaStalled(deviceId) || !state.isDeviceOnline(deviceId)) {
      await showOtaProgressDialog(context, deviceId: deviceId);
      return;
    }
    // 设备掉电、掉线或校验失败时，涂鸦可能再也不回终态。按阶段的停滞阈值让用户
    // 重新检查，而不是把他锁在一个永远不动的进度上。
    final retry = await showAppConfirmDialog(
      context,
      title: state.otaProgressFor(deviceId)?.verifyingVersion == true
          ? '暂未确认升级结果'
          : '升级似乎已中断',
      message: state.otaProgressFor(deviceId)?.verifyingVersion == true
          ? '尚未收到设备版本确认。可以重新检查固件；请保持设备通电并连接 Wi-Fi。'
          : '设备已经很久没有回报升级进度。可以重新检查固件；'
                '若设备仍在升级中，请等它完成后再试。',
      confirmLabel: '重新检查',
      icon: Icons.sync_problem_outlined,
    );
    note('固件 · 停滞/待确认提示，用户选择：${retry ? '重新检查' : '取消'}');
    if (!retry || !context.mounted) return;
    state.clearOtaProgress(deviceId);
  }

  if (!state.isDeviceOnline(deviceId)) {
    if (state.isMowerDevice(device)) {
      showMowerOfflineNotice(context);
    } else {
      showAppMessage(context, deviceOfflineMessage, tone: AppMessageTone.info);
    }
    return;
  }

  state.setCheckingFirmware(deviceId, true);
  try {
    note('固件 → $deviceId 检查新版本（涂鸦 OTA，非 DP）');
    // 每次点进来都现问涂鸦：红点那次的结论可能已经过时（例如设备其实已经升好）。
    final update = await state.checkFirmware(deviceId);
    if (!context.mounted || !state.isDeviceOnline(deviceId)) return;
    // 「当前版本」优先用同一条 OTA 记录里的那个：设备可能有 MCU、Wi-Fi 模块几个可升级
    // 组件，拿设备上报的版本和另一个组件的新版本并排显示，两行就对不上。
    final currentVersion = update?.currentVersion ?? device.firmwareVersion;
    note(
      '固件 ← 当前 $currentVersion，可升级 ${update?.version ?? '无'}'
      '${update == null ? '' : '（升级方式 ${update.upgradeType.name}）'}',
    );
    if (update == null || update.version == currentVersion) {
      showAppMessage(context, '当前已是最新固件版本');
      return;
    }
    if (update.inProgress) {
      // SDK 说这台正在升级（例如升级中途关掉 App 后重开）：`checkFirmware` 已经接回了
      // 这次任务（只挂监听、不重新下发），这里直接打开进度弹层接着走。
      if (state.otaProgressFor(deviceId)?.status != OtaStatus.running) {
        final result = await state.upgradeFirmware(deviceId, update.version);
        if (!context.mounted) return;
        if (!result.success) {
          showDeviceActionResult(context, result);
          return;
        }
      }
      await showOtaProgressDialog(context, deviceId: deviceId);
      return;
    }
    if (!confirmed) {
      // 确认框开着的时候不转圈。
      state.setCheckingFirmware(deviceId, false);
      final accepted = await showFirmwareUpdateDialog(
        context,
        currentVersion: currentVersion,
        availableVersion: update.version,
      );
      note('固件 · 检查更新确认框，用户选择：${accepted ? '立即更新' : '取消'}');
      if (!accepted || !context.mounted) return;
      state.setCheckingFirmware(deviceId, true);
    }
    if (!state.isDeviceOnline(deviceId)) {
      showAppMessage(context, deviceOfflineMessage, tone: AppMessageTone.info);
      return;
    }
    // 检测仍可查看版本；用户确认且弹框完整退出后，按最新充电状态决定是否发起。
    if (state.isMowerDevice(device)) {
      final allowed = await state.canStartFirmwareUpgrade(deviceId);
      if (!context.mounted) return;
      if (!allowed) {
        note('固件 ✗ 割草机未在桩充电，不发起升级');
        showAppMessage(
          context,
          state.isDeviceOnline(deviceId) ? '请回桩进行ota升级' : deviceOfflineMessage,
          tone: AppMessageTone.info,
        );
        return;
      }
    }
    final result = await state.upgradeFirmware(deviceId, update.version);
    note(
      result.success
          ? '固件 → 已发起升级到 ${update.version}'
          : '固件 ✗ 发起失败：${result.message}',
    );
    if (!context.mounted) return;
    if (!result.success) {
      showDeviceActionResult(context, result);
      return;
    }
    await showOtaProgressDialog(context, deviceId: deviceId);
  } on TuyaException catch (error) {
    // SDK 的原始码对用户没有意义，message 才是能照着做的那句。
    note('固件 ✗ 检查失败：${error.code} ${error.message}');
    if (context.mounted) {
      showAppMessage(
        context,
        '固件检查失败：${error.message}',
        tone: AppMessageTone.error,
      );
    }
  } catch (error) {
    note('固件 ✗ 检查失败：$error');
    if (context.mounted) {
      showAppMessage(context, '固件检查失败：$error', tone: AppMessageTone.error);
    }
  } finally {
    state.setCheckingFirmware(deviceId, false);
  }
}

Future<bool> showFirmwareUpdateDialog(
  BuildContext context, {
  required String currentVersion,
  required String availableVersion,
}) async {
  ModalRoute<bool>? route;
  var resolved = false;
  void close(BuildContext dialogContext, bool accepted) {
    if (resolved) return;
    resolved = true;
    route = ModalRoute.of<bool>(dialogContext);
    Navigator.pop(dialogContext, accepted);
  }

  final accepted =
      await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .42),
        builder: (dialogContext) => Dialog(
          key: const Key('firmware-update-dialog'),
          // **居中**（产品 2026-09-12：「检查更新弹框要居中」）。
          //
          // 这里推翻了 2026-09-11 的口径——那次两个弹框一起贴了底。现在两个各归各位：
          // 「检查更新」是个要看清版本号、需要做决定的框，居中；点了「立即更新」之后
          // 的进度层才是底部弹层（见 `showOtaProgressDialog`）。alignment 不写就是
          // Flutter 默认的居中，insetPadding 也回到默认的左右 40 / 上下 24。
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 327),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 稿子 214:5981：左右 38，标题到版本 20、两行间 11、到分隔线 30。
                Flexible(
                  child: AppDialogScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(38, 28, 38, 30),
                      child: Column(
                        children: <Widget>[
                          Text(
                            '检查更新',
                            style: AppTypography.deviceTitle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _FirmwareVersionRow(
                            label: '当前版本',
                            version: _displayVersion(currentVersion),
                          ),
                          const SizedBox(height: 11),
                          _FirmwareVersionRow(
                            label: '发现新版本',
                            version: _displayVersion(availableVersion),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                IntrinsicHeight(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextButton(
                          key: const Key('postpone-firmware-update'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            foregroundColor: AppColors.textSecondary,
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: () => close(dialogContext, false),
                          child: Text(
                            '稍后',
                            style: AppTypography.status.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: TextButton(
                          key: const Key('install-firmware-update'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            foregroundColor: AppColors.brandPrimary,
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: () => close(dialogContext, true),
                          child: Text(
                            '立即更新',
                            style: AppTypography.status.copyWith(
                              color: AppColors.brandPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
  // pop 先返回结果，等待退场动画和遮罩移除后再继续升级。
  await route?.completed;
  return accepted;
}

String _displayVersion(String version) =>
    version.startsWith('V') ? version : 'V$version';

class _FirmwareVersionRow extends StatelessWidget {
  const _FirmwareVersionRow({required this.label, required this.version});

  final String label;
  final String version;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: AppTypography.status)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            version,
            textAlign: TextAlign.end,
            style: AppTypography.status,
          ),
        ),
      ],
    );
  }
}
