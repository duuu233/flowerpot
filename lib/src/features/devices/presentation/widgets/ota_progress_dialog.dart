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
/// ## 形态：满宽的底部弹层
///
/// 产品口径几经调整，现在是（2026-09-12）：**「检查更新」居中，「固件升级中」贴底、
/// 宽度铺满屏幕、其余区域盖一层黑色半透明遮罩**——也就是常见的底部弹层。
///
/// 沿革（别再改回去）：
/// - 2026-09-11：两个弹框一起贴底，都保持卡片形态（左右留 40）。当时特意写过
///   「不要改成满宽，那等于重做视觉」。
/// - 2026-09-12：产品明确要这两个**各归各位**——决策框居中，进度层做成满宽底部弹层。
///   所以上面那句话作废了，这里就是按满宽实现的。
///
/// 实现没用 `showModalBottomSheet`：进度层要**跑完才允许关**（`PopScope`），而
/// bottom sheet 的下拉关闭、`isDismissible` 那套还得再一个个关掉；用 `showDialog` +
/// `insetPadding: EdgeInsets.zero` + `alignment: bottomCenter` 更直接，遮罩也就是
/// dialog 自己的 barrier。
/// 升级进行中的那句状态，「其他设置」的功能行和进度弹层共用。
///
/// 2026-09-15 产品：设备还没开始回报进度时一直写「0%」，用户以为卡住了。所以按
/// [OtaProgress.displayStage] 换文案：准备中 → 升级中（带百分比）→ 安装中。
///
/// 2026-09-17 产品：安装中从 **[OtaProgress.installingPercent]%（98）** 就开始——
/// 涂鸦的进度走到 98 之后要停一大段等设备写固件、重启，停在「固件升级中 98%」像卡死了。
String otaRunningLabel(OtaProgress? ota, {bool withPercent = false}) {
  final stage = ota?.displayStage ?? OtaStage.preparing;
  return switch (stage) {
    OtaStage.preparing => '固件准备中',
    OtaStage.upgrading => withPercent
        ? '固件升级中 ${(ota?.percent ?? 0).clamp(0, 100)}%'
        : '固件升级中',
    OtaStage.installing => '固件安装中',
    OtaStage.waitingWake => '等待设备唤醒',
  };
}

/// 进行中时标题下面那句提示。
String _runningHint(OtaStage stage) => switch (stage) {
  OtaStage.preparing => '正在准备固件，开始升级后会显示进度，请保持设备通电、不要断开 Wi-Fi。',
  OtaStage.upgrading => '升级过程中请保持设备通电，不要断开 Wi-Fi。',
  OtaStage.installing => '设备正在安装新固件，完成后会自动重启，请勿断电。',
  OtaStage.waitingWake => '设备唤醒后会自动开始升级，请保持设备通电。',
};

Future<void> showOtaProgressDialog(
  BuildContext context, {
  required String deviceId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    // 其余区域的黑色半透明遮罩。和「检查更新」那个框用同一个浓度。
    barrierColor: Colors.black.withValues(alpha: .42),
    builder: (_) => _OtaProgressDialog(deviceId: deviceId),
  );
}

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
    final stage = ota?.displayStage ?? OtaStage.preparing;
    // 准备中 / 安装中 / 等待唤醒没有可信的百分比：进度条改成来回走的动画、不写数字，
    // 让人看得出在跑，而不是停在 0%（或者 2026-09-17 之后的 98%）。三段共用同一套
    // 动效，产品口径就是「98% 之后换成最开始那个动效」。
    final indeterminate = running && stage != OtaStage.upgrading;
    return PopScope(
      // 升级中不许返回键关掉：关了就再也看不到进度，用户只会以为升级没在跑。
      canPop: !running,
      child: Dialog(
        key: const Key('ota-progress-dialog'),
        backgroundColor: AppColors.surface,
        // 满宽贴底：左右不留边，只有顶部两个角是圆的——底部弹层的样子。
        insetPadding: EdgeInsets.zero,
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SizedBox(
          // `Dialog` 给子件的是松约束，不写这一行卡片会缩成内容宽度。
          width: double.infinity,
          child: Padding(
            // 底边在系统手势区之上再留 20：全屏手势的机型底部有 home indicator。
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.viewPaddingOf(context).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  switch (status) {
                    OtaStatus.running => otaRunningLabel(ota),
                    OtaStatus.success => '升级完成',
                    OtaStatus.failed => '升级失败',
                  },
                  key: const Key('ota-progress-title'),
                  textAlign: TextAlign.center,
                  style: AppTypography.sectionTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: AppSpacing.lg),
                ClipRRect(
                  borderRadius: AppRadius.full,
                  child: LinearProgressIndicator(
                    key: const Key('ota-progress-bar'),
                    minHeight: 8,
                    // 失败时把进度条停在最后一次收到的百分比上，别归零——那看着
                    // 像从头再来。
                    value: indeterminate
                        ? null
                        : status == OtaStatus.success
                        ? 1
                        : percent / 100,
                    backgroundColor: AppColors.canvas,
                    color: status == OtaStatus.failed
                        ? AppColors.danger
                        : AppColors.brandPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  // 不写数字时留一行空白，弹层高度不跟着跳。
                  indeterminate
                      ? ''
                      : status == OtaStatus.success
                      ? '100%'
                      : '$percent%',
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
                    OtaStatus.running => _runningHint(stage),
                    OtaStatus.success => '设备已升级到新版本。',
                    OtaStatus.failed => ota?.message ?? '请稍后重试。',
                  },
                  textAlign: TextAlign.center,
                  style: AppTypography.smallBody,
                ),
                // 跑完（成功或失败）才给关闭按钮；升级中不给，避免用户以为能中断。
                if (!running) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    key: const Key('ota-progress-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('知道了'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
