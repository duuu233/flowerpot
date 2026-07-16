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
          const Icon(
            Icons.calendar_month_outlined,
            size: 16,
            color: AppColors.brandPrimary,
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
          const Icon(
            Icons.battery_5_bar_rounded,
            size: 18,
            color: AppColors.brandPrimary,
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
