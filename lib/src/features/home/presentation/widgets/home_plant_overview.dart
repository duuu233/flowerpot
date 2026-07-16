import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/home_dashboard_model.dart';
import 'home_companion_badge.dart';
import 'home_orbit_decoration.dart';

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
                top: 6,
                left: (width - 252) / 2,
                child: const HomeOrbitDecoration(),
              ),
              Positioned(
                top: 44,
                left: (width - 106) / 2,
                child: const AppDevicePlaceholder(hasPlant: true),
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
              Positioned(
                top: 145,
                left: 2,
                width: metricWidth,
                height: 54,
                child: _HomeMetricCard(
                  data: model.metrics[2],
                  onTap: onMetricTap,
                ),
              ),
              Positioned(
                top: 154,
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

class _HomeMetricCard extends StatelessWidget {
  const _HomeMetricCard({required this.data, required this.onTap});

  final HomeMetricData data;
  final ValueChanged<HomeMetricKind> onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (data.kind) {
      HomeMetricKind.water => (Icons.water_drop_outlined, AppColors.info),
      HomeMetricKind.light => (Icons.wb_sunny_outlined, AppColors.warning),
      HomeMetricKind.temperature => (
        Icons.device_thermostat_rounded,
        AppColors.brandDark,
      ),
      HomeMetricKind.humidity => (Icons.water_drop_rounded, AppColors.infoDark),
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
            icon: icon,
            color: color,
            backgroundColor: AppColors.surface,
            size: 32,
            iconSize: 19,
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
