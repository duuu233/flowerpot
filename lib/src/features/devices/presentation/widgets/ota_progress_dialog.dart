import 'package:flutter/material.dart';

import '../../../../app/flowerpot_app.dart';
import '../../../../design_system/design_system.dart';
import '../../../../tuya/tuya_models.dart';

/// 固件升级进度弹层：点「立即更新」之后贴在页面**底部**，一条进度条加百分比。
///
/// 升级要跑几分钟，`startOta` 一返回就只剩事件通道在推进度（见
/// `FlowerpotState.otaUpdates`）。之前进度只写在「其他设置」的那一行上，用户点完
/// 更新看不出有没有在动；这里把它摊开成弹层，跑完（成功或失败）才允许关。
///
/// ## 位置：底部，不居中
///
/// 产品口径（2026-09-11）：**OTA 升级的弹框底部定位，不要在中间。** 整条升级动线的两个
/// 弹框（「检查更新」`showFirmwareUpdateDialog` 和这个进度层）都按底部对齐，中途不会从
/// 居中跳到底部。
///
/// 实现上只改**位置**，卡片本身的样式一点没动——`alignment` 给到 `bottomCenter`，
/// `insetPadding` 的底边留出系统手势区（[_otaDialogInsetPadding]）。**不要改成
/// `showModalBottomSheet`**：那会把卡片拉成满宽、顶部切成两个直角，等于重做视觉。
Future<void> showOtaProgressDialog(
  BuildContext context, {
  required String deviceId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OtaProgressDialog(deviceId: deviceId),
  );
}

/// 底部对齐的弹框留边：左右沿用 Flutter 默认的 40，底边在系统手势区之上再留 16。
///
/// 不写死一个数，是因为全屏手势导航的机型底部有一条 home indicator，贴着画会被压住。
EdgeInsets _otaDialogInsetPadding(BuildContext context) => EdgeInsets.fromLTRB(
  40,
  24,
  40,
  MediaQuery.viewPaddingOf(context).bottom + 16,
);

class _OtaProgressDialog extends StatelessWidget {
  const _OtaProgressDialog({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final ota = state.otaProgressFor(deviceId);
    final status = ota?.status ?? OtaStatus.running;
    final percent = (ota?.percent ?? 0).clamp(0, 100);
    final running = status == OtaStatus.running;
    return PopScope(
      // 升级中不许返回键关掉：关了就再也看不到进度，用户只会以为升级没在跑。
      canPop: !running,
      child: AlertDialog(
        key: const Key('ota-progress-dialog'),
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        // 贴底，不居中（产品口径，见文件头）。
        alignment: Alignment.bottomCenter,
        insetPadding: _otaDialogInsetPadding(context),
        title: Text(
          switch (status) {
            OtaStatus.running => '固件升级中',
            OtaStatus.success => '升级完成',
            OtaStatus.failed => '升级失败',
          },
          style: AppTypography.sectionTitle.copyWith(fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ClipRRect(
              borderRadius: AppRadius.full,
              child: LinearProgressIndicator(
                key: const Key('ota-progress-bar'),
                minHeight: 8,
                // 失败时把进度条停在最后一次收到的百分比上，别归零——那看着像
                // 从头再来。
                value: status == OtaStatus.success ? 1 : percent / 100,
                backgroundColor: AppColors.canvas,
                color: status == OtaStatus.failed
                    ? AppColors.danger
                    : AppColors.brandPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              status == OtaStatus.success ? '100%' : '$percent%',
              key: const Key('ota-progress-percent'),
              textAlign: TextAlign.center,
              style: AppTypography.sectionTitle.copyWith(
                color: AppColors.brandPrimary,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              switch (status) {
                OtaStatus.running => '升级过程中请保持设备通电，不要断开 Wi-Fi。',
                OtaStatus.success => '设备已升级到新版本。',
                OtaStatus.failed => ota?.message ?? '请稍后重试。',
              },
              textAlign: TextAlign.center,
              style: AppTypography.smallBody,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: running
            ? null
            : <Widget>[
                FilledButton(
                  key: const Key('ota-progress-close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ],
      ),
    );
  }
}
