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
            // 稿子上快捷项的箭头是 16（2026-09-23 按 Figma 156:4304 核对，原来 14）。
            trailing: const AppTrailingChevron(size: 16),
            onTap: () => onActionTap(action.kind),
          ),
      ],
    );
  }

  String _assetFor(HomeActionKind kind) => switch (kind) {
    HomeActionKind.animation => AppAssets.customAnimationIcon,
    // 与另外三张同风格的一张，不用设置页那枚描边问号（风格对不上）。
    HomeActionKind.help => AppAssets.helpCenterIcon,
    HomeActionKind.settings => AppAssets.deviceSettingsIcon,
  };
}
