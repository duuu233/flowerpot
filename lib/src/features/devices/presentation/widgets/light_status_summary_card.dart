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
                          assetPath: AppAssets.statusLightIcon,
                          semanticLabel: '光照状态',
                          backgroundColor: Colors.transparent,
                          size: 40,
                          iconSize: 40,
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
                  assetPath: AppAssets.statusLightIcon,
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
                  assetPath: AppAssets.plantSelectionBadgeIcon,
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
    required this.assetPath,
    required this.value,
    required this.unit,
  });

  final String assetPath;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        AppIconBadge(
          assetPath: assetPath,
          backgroundColor: Colors.transparent,
          size: 48,
          iconSize: 48,
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
    );
  }
}
