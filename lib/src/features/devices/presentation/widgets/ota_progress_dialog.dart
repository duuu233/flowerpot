import 'dart:async';

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
/// [stageOverride] 用于弹层里「98% 先亮一拍」那段：那一刻模型已经算进安装中了，
/// 但界面还要再说一句「固件升级中」。只有弹层会传，功能行照常跟着模型走。
String otaRunningLabel(
  OtaProgress? ota, {
  bool withPercent = false,
  OtaStage? stageOverride,
}) {
  if (ota?.verifyingVersion == true) return '正在确认升级结果';
  final stage = stageOverride ?? ota?.displayStage ?? OtaStage.preparing;
  return switch (stage) {
    OtaStage.preparing => '固件准备中',
    OtaStage.upgrading =>
      withPercent && (ota?.percent ?? 0) > 0
          ? '固件升级中 ${(ota?.percent ?? 0).clamp(0, 100)}%'
          : '固件升级中',
    OtaStage.installing => '固件安装中',
    OtaStage.waitingWake => '等待设备唤醒',
  };
}

/// 进行中时标题下面那句提示。
String _runningHint(OtaStage stage) => switch (stage) {
  OtaStage.preparing => '正在准备固件，请保持设备通电、不要断开 Wi-Fi。',
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

class _OtaProgressDialog extends StatefulWidget {
  const _OtaProgressDialog({required this.deviceId});

  final String deviceId;

  @override
  State<_OtaProgressDialog> createState() => _OtaProgressDialogState();
}

class _OtaProgressDialogState extends State<_OtaProgressDialog> {
  /// 切进「固件安装中」之前，先把 98% 亮够这么久。
  ///
  /// 2026-09-18 用户：涂鸦的进度常常从 9x **直接**跳进安装中，98% 一闪而过、甚至根本
  /// 没露过面，看上去就是「92% 之后忽然换了一句话」，很突兀。先让 98% 站住一拍再换，
  /// 过渡才接得上。
  ///
  /// 这**只是显示上的一拍**：设备该写固件还写固件，成功事件随时来随时切「升级完成」
  /// （[_holding] 第一条就把非 running 排除了），不会因为这 0.9 秒少显示什么。
  static const _holdAt98 = Duration(milliseconds: 900);

  Timer? _holdTimer;
  Timer? _stallTimer;

  @override
  void initState() {
    super.initState();
    // A stalled SDK may never send another event to rebuild this dialog.
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  bool _held98 = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _stallTimer?.cancel();
    super.dispose();
  }

  /// 此刻是否正处在「98% 亮相」那一拍。
  ///
  /// ⚠️ 只拦「进度自己走到了 98」这一条路径。涂鸦直接报阶段 6（固件已下载到设备）
  /// 而进度还很低时**不能**假装 98%——那是个设备从没报过的数字。
  bool _holding(OtaProgress? ota, OtaStage rawStage) {
    if (_held98 || ota?.verifyingVersion == true) return false;
    if (ota?.status != OtaStatus.running) return false;
    if (rawStage != OtaStage.installing) return false;
    if ((ota?.percent ?? 0) < OtaProgress.installingPercent) return false;
    _holdTimer ??= Timer(_holdAt98, () {
      if (!mounted) return;
      setState(() => _held98 = true);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final ota = state.otaProgressFor(widget.deviceId);
    final status = ota?.status ?? OtaStatus.running;
    final running = status == OtaStatus.running;
    final verifying = running && ota?.verifyingVersion == true;
    final stalled = running && state.otaStalled(widget.deviceId);
    if (!running) _stallTimer?.cancel();
    final rawStage = ota?.displayStage ?? OtaStage.preparing;
    // 亮相那一拍：文案回到「固件升级中」、进度条钉在 98%，一拍过后才换成安装中。
    final holdingAt98 = _holding(ota, rawStage);
    final stage = holdingAt98 ? OtaStage.upgrading : rawStage;
    final percent = holdingAt98
        ? OtaProgress.installingPercent
        : (ota?.percent ?? 0).clamp(0, 100);
    // 准备中 / 安装中 / 等待唤醒没有可信的百分比：进度条改成来回走的动画、不写数字，
    // 让人看得出在跑，而不是停在 0%（或者 2026-09-17 之后的 98%）。三段共用同一套
    // 动效，产品口径就是「98% 之后换成最开始那个动效」。
    final indeterminate =
        running && (stage != OtaStage.upgrading || percent == 0);
    return PopScope(
      // 升级中不许返回键关掉：关了就再也看不到进度，用户只会以为升级没在跑。
      canPop: !running || stalled || verifying,
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
                Flexible(
                  child: AppDialogScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          stalled
                              ? (verifying ? '暂未确认升级结果' : '暂未收到升级进度')
                              : switch (status) {
                                  OtaStatus.running => otaRunningLabel(
                                    ota,
                                    stageOverride: stage,
                                  ),
                                  OtaStatus.success => '升级完成',
                                  OtaStatus.failed => '升级失败',
                                },
                          key: const Key('ota-progress-title'),
                          textAlign: TextAlign.center,
                          style: AppTypography.sectionTitle.copyWith(
                            fontSize: 17,
                          ),
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
                            OtaStatus.running =>
                              verifying
                                  ? (stalled
                                        ? '暂未确认设备版本，请保持设备通电并连接 Wi-Fi。可以关闭窗口，稍后重新检查；关闭不会中断设备升级。'
                                        : '设备可能正在安装或重启，正在等待版本确认。请保持设备通电、不要断开 Wi-Fi；关闭窗口不会中断升级。')
                                  : stalled
                                  ? '设备可能仍在升级，请保持通电、不要断开 Wi-Fi。可以关闭窗口，稍后重新检查；关闭不会中断设备升级。'
                                  : _runningHint(stage),
                            OtaStatus.success => '设备已升级到新版本。',
                            OtaStatus.failed => ota?.message ?? '请稍后重试。',
                          },
                          textAlign: TextAlign.center,
                          style: AppTypography.smallBody,
                        ),
                      ],
                    ),
                  ),
                ),
                // 跑完（成功或失败）才给关闭按钮；升级中不给，避免用户以为能中断。
                if (!running || stalled || verifying) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    key: const Key('ota-progress-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(stalled || verifying ? '关闭窗口' : '知道了'),
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
