import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/mine_page_model.dart';

class MineMenuList extends StatelessWidget {
  const MineMenuList({
    required this.items,
    required this.onItemTap,
    required this.height,
    super.key,
  });

  final List<MineMenuItem> items;
  final ValueChanged<MineMenuKind> onItemTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: AppSettingsList(
        showDividers: false,
        showShadow: false,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),
          for (final item in items)
            AppSettingsTile(
              title: item.label,
              value: item.trailingValue,
              minTileHeight: 48,
              contentPadding: const EdgeInsets.symmetric(horizontal: 32),
              leading: Image.asset(
                _assetFor(item.kind),
                width: 26,
                height: 26,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                semanticLabel: item.label,
              ),
              titleStyle: AppTypography.status.copyWith(fontSize: 16),
              onTap: () => onItemTap(item.kind),
            ),
        ],
      ),
    );
  }

  String _assetFor(MineMenuKind kind) => switch (kind) {
    MineMenuKind.personalInfo => AppAssets.profileMenuPersonalInfoIcon,
    MineMenuKind.accountSecurity => AppAssets.profileMenuAccountSecurityIcon,
    MineMenuKind.deviceSettings => AppAssets.deviceSettingsIcon,
    MineMenuKind.helpCenter => AppAssets.profileMenuHelpIcon,
    MineMenuKind.feedback => AppAssets.profileMenuFeedbackIcon,
    MineMenuKind.privacyPolicy => AppAssets.profileMenuPrivacyIcon,
    MineMenuKind.userAgreement => AppAssets.profileMenuAgreementIcon,
    MineMenuKind.about => AppAssets.profileMenuAboutIcon,
  };
}
