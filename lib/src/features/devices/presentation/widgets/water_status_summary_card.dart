import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/water_status_page_model.dart';

class WaterStatusSummaryCard extends StatelessWidget {
  const WaterStatusSummaryCard({required this.model, super.key});

  final WaterStatusPageModel model;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderRadius: AppRadius.card,
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const SizedBox(
                width: 112,
                child: Center(
                  child: AppDevicePlaceholder(hasPlant: true, width: 84),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        AppIconBadge(
                          icon: Icons.water_drop_outlined,
                          color: AppColors.info,
                          backgroundColor: AppColors.info.withValues(
                            alpha: .11,
                          ),
                          size: 40,
                          iconSize: 24,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Text(
                            model.status,
                            style: AppTypography.deviceTitle.copyWith(
                              color: AppColors.info,
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
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: _WaterMetric(
                  icon: Icons.water_outlined,
                  color: AppColors.info,
                  backgroundColor: AppColors.info.withValues(alpha: .11),
                  value: '${model.waterLevel}',
                  unit: 'ml',
                  label: '当前水仓水位',
                ),
              ),
              const SizedBox(
                height: 38,
                child: VerticalDivider(color: AppColors.divider),
              ),
              Expanded(
                child: _WaterMetric(
                  icon: Icons.water_drop_outlined,
                  color: AppColors.success,
                  backgroundColor: AppColors.successSurface,
                  value: '${model.soilMoisture}',
                  unit: '%',
                  label: '当前土壤湿度',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaterMetric extends StatelessWidget {
  const _WaterMetric({
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.value,
    required this.unit,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        AppIconBadge(
          icon: icon,
          color: color,
          backgroundColor: backgroundColor,
          size: 48,
          iconSize: 28,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
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
                        text: value,
                        style: AppTypography.deviceTitle.copyWith(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: ' $unit',
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
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
