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
                          size: 32,
                          iconSize: 32,
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
          // 两组指标与中间竖线，尺寸量自 `docs/UI/需水状态-水仓水位变化.png`（375 宽）：
          // 左图标距卡片左边 26、右组内容收在距卡片右边 22 处，竖线 1 宽 #EAEAEA 高约 30、
          // 左右各留 9，两组各占一半（约 134）且都**靠左排**。
          //
          // 原来的问题：`VerticalDivider` 的宽度取的是主题 `dividerTheme.space`（=1），
          // 不是默认的 16，竖线两边一点留白都没有；两组又各自在半边里居中，14 号标签
          // 把半边撑满之后，右边那组的图标就直接贴在竖线上，看着像压住了。
          Padding(
            padding: const EdgeInsets.only(
              left: _metricRowInsetStart,
              right: _metricRowInsetEnd,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _WaterMetric(
                    key: const Key('water-metric-level'),
                    assetPath: AppAssets.waterLevelIcon,
                    value: '${model.waterLevel}',
                    unit: 'ml',
                    label: '当前水仓水位',
                  ),
                ),
                Container(
                  key: const Key('water-metric-divider'),
                  width: 1,
                  height: 30,
                  margin: const EdgeInsets.symmetric(
                    horizontal: _metricDividerGap,
                  ),
                  color: AppColors.divider,
                ),
                Expanded(
                  child: _WaterMetric(
                    key: const Key('water-metric-soil'),
                    assetPath: AppAssets.waterStatusIcon,
                    value: '${model.soilMoisture}',
                    unit: '%',
                    label: '当前土壤湿度',
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

/// 指标行在卡片内边距（18）之外再往里收的量。左 18 + 8 = 26 对上设计稿左图标的位置；
/// 右 18 + 4 = 22 对上右组「当前土壤湿度 ⓘ」收尾的位置。两边不等是量出来的，不是笔误。
const double _metricRowInsetStart = 8;
const double _metricRowInsetEnd = 4;

/// 竖线左右的留白。
const double _metricDividerGap = 9;

class _WaterMetric extends StatelessWidget {
  const _WaterMetric({
    required this.assetPath,
    super.key,
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
    // 图标 40（资源自带浅色圆底）、图标与文字间距 8、数值 20、标签 12、提示图标 12，
    // 量自设计稿。窄屏（320 宽）上半边只剩一百出头，数值和标签各自按比例缩小，
    // 不换行、不溢出到竖线那边。
    return Row(
      children: <Widget>[
        AppIconBadge(
          assetPath: assetPath,
          backgroundColor: Colors.transparent,
          size: 40,
          iconSize: 40,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      TextSpan(
                        text: ' $unit',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Image.asset(
                      AppAssets.infoIcon,
                      width: 12,
                      height: 12,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
