import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'device_plant_artwork.dart';
import 'status_metric_icon.dart';
import '../../models/battery_status_page_model.dart';

class BatteryStatusSummaryCard extends StatelessWidget {
  const BatteryStatusSummaryCard({required this.model, super.key});

  final BatteryStatusPageModel model;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      borderRadius: AppRadius.card,
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 100,
                child: Center(
                  child: DevicePlantArtwork(
                    deviceId: model.deviceId,
                    width: 100,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const ChargingBatteryBadge(size: 32),
                        const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Text(
                            model.status,
                            style: AppTypography.deviceTitle.copyWith(
                              color: AppColors.brandPrimary,
                              fontSize: 19,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _TwoLineDescription(text: model.description),
                    const SizedBox(height: AppSpacing.md),
                    const Divider(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 图标大小、位置与需水卡一致，见 StatusMetricIcon（2026-09-15 产品：和光照、
          // 湿度那几页是同一个问题）。
          Row(
            children: <Widget>[
              const SizedBox(width: StatusMetricIcon.rowInsetStart),
              const StatusMetricIcon(
                assetPath: AppAssets.batteryStatusIcon,
                semanticLabel: '电池电量',
              ),
              const SizedBox(width: StatusMetricIcon.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: '${model.battery}',
                              style: AppTypography.deviceTitle.copyWith(
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: ' %',
                              style: AppTypography.body.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '当前电池状态',
                          style: AppTypography.body.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Image.asset(
                          AppAssets.infoIcon,
                          width: 14,
                          height: 14,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 状态描述：**固定至少占两行高度**（2026-09-15 产品：「充电中」下面的描述长短随状态变，
/// 不固定的话整块会跳来跳去）。
///
/// 高度靠一段看不见的两行占位撑住，而不是写死像素：跟着系统字号缩放走，文字真超过两行
/// 时也照常换行、不截断。
class _TwoLineDescription extends StatelessWidget {
  const _TwoLineDescription({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.body.copyWith(
      height: 1.55,
      color: AppColors.textSecondary,
    );
    return Stack(
      key: const Key('battery-status-description'),
      children: <Widget>[
        ExcludeSemantics(
          child: Opacity(
            opacity: 0,
            child: Text('\u00A0\n\u00A0', style: style),
          ),
        ),
        Text(text, style: style),
      ],
    );
  }
}

/// 顶部状态行的电池图标。
class ChargingBatteryBadge extends StatelessWidget {
  const ChargingBatteryBadge({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.batteryIcon,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '电池状态',
    );
  }
}
