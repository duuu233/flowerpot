import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/home_dashboard_model.dart';
import 'home_companion_badge.dart';

class HomePlantOverview extends StatelessWidget {
  const HomePlantOverview({
    required this.model,
    required this.onMetricTap,
    super.key,
  });

  final HomeDashboardModel model;
  final ValueChanged<HomeMetricKind> onMetricTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 253,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final metricWidth = (width * .32).clamp(92.0, 106.0).toDouble();
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                top: 34,
                left: (width - 132) / 2,
                child: _PlantHeroImage(imageUrl: model.plantImageUrl),
              ),
              Positioned(
                top: 42,
                left: 0,
                width: metricWidth,
                height: 54,
                child: _HomeMetricCard(
                  data: model.metrics[0],
                  onTap: onMetricTap,
                ),
              ),
              Positioned(
                top: 42,
                right: 0,
                width: metricWidth,
                height: 54,
                child: _HomeMetricCard(
                  data: model.metrics[1],
                  onTap: onMetricTap,
                ),
              ),
              // 下面两张和上面两张同宽同高，左右也贴同一条边：空气温度曾经
              // left: 2、相对湿度 top: 154，四张卡片看着就是歪的。
              Positioned(
                top: 145,
                left: 0,
                width: metricWidth,
                height: 54,
                child: _HomeMetricCard(
                  data: model.metrics[2],
                  onTap: onMetricTap,
                ),
              ),
              Positioned(
                top: 145,
                right: 0,
                width: metricWidth,
                height: 54,
                child: _HomeMetricCard(
                  data: model.metrics[3],
                  onTap: onMetricTap,
                ),
              ),
              if (model.showCompanionSummary)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: HomeCompanionBadge(
                      companionDays: model.companionDays,
                      battery: model.battery,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 已绑定设备首页正中那张图：优先用后台给这株植物配的图片
/// （`getProductPlantList` 的 `plantImg`，经 `PlantProfile.imageUrl` 带过来），
/// 没有配、或者取不回来时才回落到本地静态图。植物详情页 `_PlantDetailArtwork`
/// 是同一套口径。
class _PlantHeroImage extends StatelessWidget {
  const _PlantHeroImage({required this.imageUrl});

  static const double _width = 132;
  static const double _height = 170;

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return _fallback();
    return Image.network(
      url,
      width: _width,
      height: _height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '设备当前的植物',
      errorBuilder: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() => Image.asset(
    AppAssets.smartPlanterWithPlant,
    width: _width,
    height: _height,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    semanticLabel: '带植物的 YSplanter',
  );
}

class _HomeMetricCard extends StatelessWidget {
  const _HomeMetricCard({required this.data, required this.onTap});

  final HomeMetricData data;
  final ValueChanged<HomeMetricKind> onTap;

  @override
  Widget build(BuildContext context) {
    final assetPath = switch (data.kind) {
      HomeMetricKind.water => AppAssets.waterStatusIcon,
      HomeMetricKind.light => AppAssets.metricLightIcon,
      HomeMetricKind.temperature => AppAssets.metricTemperatureIcon,
      HomeMetricKind.humidity => AppAssets.statusHumidityIcon,
    };
    return AppSurfaceCard(
      onTap: () => onTap(data.kind),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.card,
      side: const BorderSide(color: AppColors.surface),
      child: Row(
        children: <Widget>[
          AppIconBadge(
            assetPath: assetPath,
            semanticLabel: data.label,
            backgroundColor: Colors.transparent,
            size: 32,
            iconSize: 32,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.label,
                    maxLines: 1,
                    style: AppTypography.smallBody.copyWith(
                      height: 1.15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.value,
                    maxLines: 1,
                    style: AppTypography.compactBody.copyWith(
                      height: 1.1,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
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
