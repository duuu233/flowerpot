import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/light_status_page_model.dart';

class LightStatusSummaryCard extends StatelessWidget {
  const LightStatusSummaryCard({required this.model, super.key});

  final LightStatusPageModel model;

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
                        const AppIconBadge(
                          icon: Icons.wb_sunny_outlined,
                          color: AppColors.warning,
                          backgroundColor: AppColors.warningSurface,
                          size: 40,
                          iconSize: 24,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          model.status,
                          style: AppTypography.deviceTitle.copyWith(
                            color: AppColors.warning,
                            fontSize: 19,
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
                child: _LightMetric(
                  icon: Icons.wb_sunny_outlined,
                  color: AppColors.warning,
                  backgroundColor: AppColors.warningSurface,
                  value: '${model.illuminance}',
                  unit: 'lux',
                ),
              ),
              const SizedBox(
                height: 38,
                child: VerticalDivider(color: AppColors.divider),
              ),
              Expanded(
                child: _LightMetric(
                  icon: Icons.eco_outlined,
                  color: AppColors.success,
                  backgroundColor: AppColors.successSurface,
                  value: model.ppfd.toStringAsFixed(3),
                  unit: 'μmol/m²/s',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LightMetric extends StatelessWidget {
  const _LightMetric({
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final String value;
  final String unit;

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
                child: Text(
                  value,
                  style: AppTypography.deviceTitle.copyWith(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        unit,
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
