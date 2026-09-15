import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'device_plant_artwork.dart';
import 'status_metric_icon.dart';
import '../../models/light_status_page_model.dart';

class LightStatusSummaryCard extends StatelessWidget {
  const LightStatusSummaryCard({required this.model, super.key});

  final LightStatusPageModel model;

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
                        const AppIconBadge(
                          assetPath: AppAssets.statusLightIcon,
                          semanticLabel: '光照状态',
                          backgroundColor: Colors.transparent,
                          size: 27,
                          iconSize: 27,
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
          const SizedBox(height: 14),
          // 两组的排法照抄需水卡：整行左收 8、右收 4，两组各占一半且都靠左排，
          // 中间竖线 1 宽、高 30、左右各留 9。原来两组在半边里居中、图标 32，
          // 看着又小又往中间挤（2026-09-15 产品）。
          Padding(
            padding: const EdgeInsets.only(
              left: StatusMetricIcon.rowInsetStart,
              right: StatusMetricIcon.rowInsetEnd,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _LightMetric(
                    key: const Key('light-metric-lux'),
                    assetPath: AppAssets.metricLightIcon,
                    value: '${model.illuminance}',
                    unit: 'lux',
                  ),
                ),
                Container(
                  key: const Key('light-metric-divider'),
                  width: 1,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  color: AppColors.divider,
                ),
                Expanded(
                  child: _LightMetric(
                    key: const Key('light-metric-ppfd'),
                    assetPath: AppAssets.plantSelectionBadgeIcon,
                    value: model.ppfd.toStringAsFixed(3),
                    unit: 'μmol/m²/s',
                  ),
                ),
              ],
            ),
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
    super.key,
  });

  final String assetPath;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        StatusMetricIcon(assetPath: assetPath),
        const SizedBox(width: StatusMetricIcon.gap),
        Expanded(
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
