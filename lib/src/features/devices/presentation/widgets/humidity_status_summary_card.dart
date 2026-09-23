import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'device_plant_artwork.dart';
import 'status_metric_icon.dart';
import '../../models/humidity_status_page_model.dart';

class HumidityStatusSummaryCard extends StatelessWidget {
  const HumidityStatusSummaryCard({required this.model, super.key});

  final HumidityStatusPageModel model;

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
                        const _HumidityBadge(size: 32),
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
          const SizedBox(height: 14),
          // 图标大小、位置与需水卡一致，见 StatusMetricIcon。湿度没有满幅的指标图标，
          // 用顶部那张带透明边的，按比例放大到可见圆底 40。
          Row(
            children: <Widget>[
              const SizedBox(width: StatusMetricIcon.rowInsetStart),
              const StatusMetricIcon(
                assetPath: AppAssets.statusHumidityIcon,
                transparentInset: StatusMetricIcon.statusIconInset,
                semanticLabel: '相对湿度',
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

class _HumidityBadge extends StatelessWidget {
  const _HumidityBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.statusHumidityIcon,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '相对湿度',
    );
  }
}
