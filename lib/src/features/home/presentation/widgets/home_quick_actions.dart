import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/home_dashboard_model.dart';

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({
    required this.actions,
    required this.onActionTap,
    super.key,
  });

  final List<HomeActionData> actions;
  final ValueChanged<HomeActionKind> onActionTap;

  @override
  Widget build(BuildContext context) {
    return AppSettingsList(
      showDividers: false,
      borderRadius: AppRadius.large,
      children: <Widget>[
        for (final action in actions)
          AppSettingsTile(
            title: action.label,
            minTileHeight: 60,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            leading: AppIconBadge(
              icon: _iconFor(action.kind),
              color: AppColors.brandPrimary,
              backgroundColor: AppColors.brandSurface,
              size: 40,
              iconSize: 21,
              borderRadius: AppRadius.large,
            ),
            titleStyle: AppTypography.status.copyWith(fontSize: 15),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              size: 26,
              color: AppColors.textSecondary,
            ),
            onTap: () => onActionTap(action.kind),
          ),
      ],
    );
  }

  IconData _iconFor(HomeActionKind kind) => switch (kind) {
    HomeActionKind.animation => Icons.smart_display_rounded,
    HomeActionKind.battery => Icons.battery_charging_full_rounded,
    HomeActionKind.settings => Icons.settings_rounded,
  };
}
