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
    super.key,
  });

  final PairingStage stage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final current = PairingStage.steps.indexOf(stage);
    return ColoredBox(
      color: AppColors.canvas,
      child: SafeArea(
        child: SingleChildScrollView(
          key: const Key('pairing-progress-view'),
          child: ResponsiveContent(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              40,
              AppSpacing.pageMargin,
              32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 220,
                  child: Image.asset(
                    AppAssets.pairingWifiSetupIllustration,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(height: 24),
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
                const SizedBox(height: 10),
                const Text(
                  '预计需要10-30秒，请勿关闭页面',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                AppSurfaceCard(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                          // stage 还是 idle 时 current 为 -1：那是刚点下按钮、
                          // 状态层还没推第一步，按「第一步进行中」画。
                          state: _stateFor(index, current < 0 ? 0 : current),
                          isLast: index == PairingStage.steps.length - 1,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
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
    required this.state,
    required this.isLast,
  });

  final int index;
  final String label;
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
                  child: state == _StepState.done
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: AppColors.surface,
                        )
                      : Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: AppColors.surface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
