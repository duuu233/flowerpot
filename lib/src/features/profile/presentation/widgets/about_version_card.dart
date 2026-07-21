import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/about_page_model.dart';

class AboutVersionCard extends StatelessWidget {
  const AboutVersionCard({
    required this.model,
    required this.onCheckUpdate,
    required this.onReleaseNotes,
    super.key,
  });

  final AboutPageModel model;
  final VoidCallback? onCheckUpdate;
  final VoidCallback? onReleaseNotes;

  @override
  Widget build(BuildContext context) {
    return AppSettingsList(
      key: const Key('about-version-card'),
      showDividers: false,
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      showShadow: false,
      children: <Widget>[
        _AboutVersionTile(
          tileKey: const Key('about-current-version'),
          icon: Icons.manage_accounts_outlined,
          label: '当前版本',
          value: model.displayVersion,
        ),
        _AboutVersionTile(
          tileKey: const Key('about-check-update'),
          icon: Icons.shield_outlined,
          label: '检查更新',
          value: model.updateStatus,
          onTap: onCheckUpdate,
        ),
        _AboutVersionTile(
          tileKey: const Key('about-release-notes'),
          icon: Icons.help_outline_rounded,
          label: '版本说明',
          onTap: onReleaseNotes,
        ),
      ],
    );
  }
}

class _AboutVersionTile extends StatelessWidget {
  const _AboutVersionTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppSettingsTile(
      key: tileKey,
      icon: icon,
      title: label,
      value: value,
      onTap: onTap,
      minTileHeight: 56,
      titleStyle: AppTypography.sectionTitle.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}
