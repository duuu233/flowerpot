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
              assetPath: _assetFor(action.kind),
              semanticLabel: action.label,
              backgroundColor: Colors.transparent,
              size: 40,
              iconSize: 40,
              borderRadius: AppRadius.large,
            ),
            titleStyle: AppTypography.status.copyWith(fontSize: 15),
            trailing: Image.asset(
              AppAssets.chevronRightIcon,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
            onTap: () => onActionTap(action.kind),
          ),
      ],
    );
  }

  String _assetFor(HomeActionKind kind) => switch (kind) {
    HomeActionKind.animation => AppAssets.customAnimationIcon,
    HomeActionKind.battery => AppAssets.batteryStatusIcon,
    HomeActionKind.settings => AppAssets.deviceSettingsIcon,
  };
}
