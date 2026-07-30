import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class HomeCompanionBadge extends StatelessWidget {
  const HomeCompanionBadge({
    required this.companionDays,
    required this.battery,
    super.key,
  });

  final int companionDays;
  final int battery;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      borderRadius: AppRadius.full,
      color: AppColors.surfaceTranslucent,
      side: const BorderSide(color: AppColors.surface),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Image.asset(
            AppAssets.calendarIcon,
            width: 16,
            height: 16,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: '陪伴天数',
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '已陪伴$companionDays天',
            style: AppTypography.compactBody.copyWith(
              height: 1,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const SizedBox(
            height: 18,
            child: VerticalDivider(color: AppColors.divider),
          ),
          const SizedBox(width: AppSpacing.sm),
          Image.asset(
            AppAssets.batteryIcon,
            width: 18,
            height: 18,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: '电量',
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$battery%',
            style: AppTypography.compactBody.copyWith(
              height: 1,
              color: AppColors.brandPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
