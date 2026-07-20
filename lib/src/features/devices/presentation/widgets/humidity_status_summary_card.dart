import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/humidity_status_page_model.dart';

class HumidityStatusSummaryCard extends StatelessWidget {
  const HumidityStatusSummaryCard({required this.model, super.key});

  final HumidityStatusPageModel model;

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
                        const _HumidityBadge(size: 40, iconSize: 24),
                        const SizedBox(width: AppSpacing.md),
                        Flexible(
                          child: Text(
                            model.status,
                            style: AppTypography.deviceTitle.copyWith(
                              color: AppColors.infoDark,
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
              const _HumidityBadge(size: 48, iconSize: 29),
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
                              text: '${model.humidity}',
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
                          '当前相对湿度',
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

class _HumidityBadge extends StatelessWidget {
  const _HumidityBadge({required this.size, required this.iconSize});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurface,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Transform.translate(
              offset: Offset(-iconSize * .12, 0),
              child: Icon(
                Icons.water_drop_outlined,
                color: AppColors.infoDark,
                size: iconSize,
              ),
            ),
            Positioned(
              right: size * .17,
              bottom: size * .21,
              child: Icon(
                Icons.water_drop_outlined,
                color: AppColors.infoDark,
                size: iconSize * .48,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
