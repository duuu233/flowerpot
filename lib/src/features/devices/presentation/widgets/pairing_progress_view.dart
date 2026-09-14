import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../../../tuya/tuya_models.dart';

/// 配网进度（`docs/UI/v2/智能花盆ysplanter/设备配网-配网中的步骤-UI页面样式.png`）。
///
/// 盖在「连接Wi-Fi」页上，而不是单独一条路由：配网是 `pairViaHotspot` 一次
/// await 走完的，中途把页面换掉就没人在等那个 Future 了，成功/失败也没地方跳。
/// 三步的状态来自 [FlowerpotState.pairingStage]。
class PairingProgressView extends StatelessWidget {
  const PairingProgressView({
    required this.stage,
    required this.onCancel,
    this.notice,
    super.key,
  });

  final PairingStage stage;
  final VoidCallback onCancel;

  /// 正在等用户处理**系统**弹框时显示的一句话（没有就传 null）。
  ///
  /// 系统入网授权框盖在这一页上面，用户点完「连接」它才消失——消失后这一页是他看到
  /// 的第一屏。写清"刚才那个框是正常步骤、现在在干什么"，比让他盯着一个没头没尾的
  /// 转圈要好。文案与按钮上方那条预告是同一口径（`PRODUCT_RULES` §4.0）。
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final current = PairingStage.steps.indexOf(stage);
    return ColoredBox(
      color: AppColors.canvas,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 这一页的内容是固定的三步，不该要用户滚动才看得到第三步——正在配网时
            // 滚走的正是他要盯的进度。插图上下的留白是唯一能让的地方：矮屏再收一档，
            // 插图本身也跟着缩，整页就能进首屏。
            final compact = constraints.maxHeight < 700;
            return SingleChildScrollView(
              key: const Key('pairing-progress-view'),
              child: ResponsiveContent(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pageMargin,
                  compact ? 12 : 20,
                  AppSpacing.pageMargin,
                  compact ? 20 : 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      height: compact ? 150 : 190,
                      child: Image.asset(
                        AppAssets.pairingWifiSetupIllustration,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        excludeFromSemantics: true,
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 16),
                    const Text(
                      '正在为设备配置网络...',
                      key: Key('pairing-progress-title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notice ?? '预计需要10-30秒，请勿关闭页面',
                      key: const Key('pairing-progress-subtitle'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 20),
                    AppSurfaceCard(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      child: Column(
                        children: <Widget>[
                          for (
                            var index = 0;
                            index < PairingStage.steps.length;
                            index++
                          )
                            _StepRow(
                              index: index,
                              label: PairingStage.steps[index].label,
                              hint: PairingStage.steps[index].hint,
                              // stage 还是 idle 时 current 为 -1：那是刚点下按钮、
                              // 状态层还没推第一步，按「第一步进行中」画。
                              state: _stateFor(index, current < 0 ? 0 : current),
                              isLast: index == PairingStage.steps.length - 1,
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 20),
                    TextButton(
                      key: const Key('pairing-progress-cancel'),
                      onPressed: onCancel,
                      child: const Text(
                        '取消配网',
                        style: TextStyle(
                          color: AppColors.brandPrimary,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  _StepState _stateFor(int index, int current) => switch (index) {
    _ when index < current => _StepState.done,
    _ when index == current => _StepState.running,
    _ => _StepState.waiting,
  };
}

enum _StepState { done, running, waiting }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.label,
    required this.hint,
    required this.state,
    required this.isLast,
  });

  final int index;
  final String label;

  /// 这一步的必要说明；只在「进行中」那一步画出来。
  final String hint;

  final _StepState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.done => AppColors.brandPrimary,
      _StepState.running => AppColors.brandPrimary,
      _StepState.waiting => AppColors.disabled,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: SizedBox.square(
                  dimension: 28,
                  child: switch (state) {
                    _StepState.done => const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.surface,
                    ),
                    // 2026-09-14 产品：正在执行的那一步画转圈，不画序号——一眼看出
                    // 「现在在哪一步、还在动」。已完成是对勾，等待中仍是序号。
                    _StepState.running => Center(
                      child: SizedBox.square(
                        key: Key('pairing-step-spinner-$index'),
                        dimension: 16,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.surface,
                        ),
                      ),
                    ),
                    _StepState.waiting => Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppColors.surface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  },
                ),
              ),
              if (!isLast)
                const Expanded(
                  child: VerticalDivider(
                    width: 28,
                    thickness: 1,
                    color: AppColors.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${index + 1}.$label',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    switch (state) {
                      _StepState.done => '已完成',
                      _StepState.running => '进行中...',
                      _StepState.waiting => '等待中',
                    },
                    style: TextStyle(
                      color: state == _StepState.running
                          ? AppColors.brandPrimary
                          : AppColors.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                  // 说明只跟着当前这一步走：三行同时铺出来，用户就不知道该看哪句。
                  if (state == _StepState.running && hint.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      key: Key('pairing-step-hint-$index'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
