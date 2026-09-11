import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'device_plant_artwork.dart';
import '../../models/water_status_page_model.dart';

class WaterStatusSummaryCard extends StatelessWidget {
  const WaterStatusSummaryCard({required this.model, super.key});

  final WaterStatusPageModel model;

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
                        AppIconBadge(
                          assetPath: AppAssets.statusWaterIcon,
                          semanticLabel: '需水状态',
                          backgroundColor: Colors.transparent,
                          size: 27,
                          iconSize: 27,
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
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _WaterMetric(
                  assetPath: AppAssets.waterLevelIcon,
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
                  assetPath: AppAssets.waterStatusIcon,
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
    required this.assetPath,
    required this.value,
    required this.unit,
    required this.label,
  });

  final String assetPath;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        AppIconBadge(
          assetPath: assetPath,
          backgroundColor: Colors.transparent,
          size: 32,
          iconSize: 32,
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
