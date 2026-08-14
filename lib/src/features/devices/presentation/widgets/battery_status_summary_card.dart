import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
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
              const SizedBox(
                width: 100,
                child: Center(
                  child: AppDevicePlaceholder(hasPlant: true, width: 100),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const ChargingBatteryBadge(size: 40),
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
                    Text(
                      model.description,
                      style: AppTypography.body.copyWith(
                        height: 1.55,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Divider(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              const SizedBox(width: 28),
              const ChargingBatteryBadge(size: 48),
              const SizedBox(width: AppSpacing.sm),
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
