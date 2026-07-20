import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/temperature_status_page_model.dart';

class TemperatureStatusSummaryCard extends StatelessWidget {
  const TemperatureStatusSummaryCard({required this.model, super.key});

  final TemperatureStatusPageModel model;

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
                          icon: Icons.device_thermostat_rounded,
                          color: AppColors.brandDark,
                          backgroundColor: AppColors.brandSurface,
                          size: 40,
                          iconSize: 24,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Text(
                            model.status,
                            style: AppTypography.deviceTitle.copyWith(
                              color: AppColors.brandDark,
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
              const SizedBox(width: 28),
              const AppIconBadge(
                icon: Icons.device_thermostat_rounded,
                color: AppColors.brandDark,
                backgroundColor: AppColors.brandSurface,
                size: 48,
                iconSize: 28,
              ),
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
                              text: model.temperature.toStringAsFixed(1),
                              style: AppTypography.deviceTitle.copyWith(
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '°C',
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
                          '当前空气温度',
                          style: AppTypography.body.copyWith(
                            color: AppColors.textSecondary,
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
          ),
        ],
      ),
    );
  }
}
