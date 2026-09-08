import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/about_page_model.dart';

class AboutVersionCard extends StatelessWidget {
  const AboutVersionCard({
    required this.model,
    required this.onCheckUpdate,
    super.key,
  });

  final AboutPageModel model;
  final VoidCallback? onCheckUpdate;

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
          assetPath: AppAssets.aboutCurrentVersionIcon,
          label: '当前版本',
          value: model.displayVersion,
        ),
        _AboutVersionTile(
          tileKey: const Key('about-check-update'),
          assetPath: AppAssets.aboutCheckUpdateIcon,
          label: '检查更新',
          value: model.updateStatus,
          onTap: onCheckUpdate,
        ),
      ],
    );
  }
}

class _AboutVersionTile extends StatelessWidget {
  const _AboutVersionTile({
    required this.tileKey,
    required this.assetPath,
    required this.label,
    this.value,
    this.onTap,
  });

  final Key tileKey;
  final String assetPath;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppSettingsTile(
      key: tileKey,
      leading: Image.asset(
        assetPath,
        width: 26,
        height: 26,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: label,
      ),
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
