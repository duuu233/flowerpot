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
          badge: model.hasUpdate,
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
    this.badge = false,
  });

  final Key tileKey;
  final String assetPath;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  /// 有新版本时行尾点红点，排在状态文字前面。
  final bool badge;

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
      trailing: badge
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const AppNoticeDot(semanticLabel: '有新版本'),
                const SizedBox(width: AppSpacing.xs),
                if (value != null) ...<Widget>[
                  Text(value!, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(width: AppSpacing.xs),
                ],
                if (onTap != null) const AppTrailingChevron(),
              ],
            )
          : null,
      onTap: onTap,
      minTileHeight: 56,
      titleStyle: AppTypography.sectionTitle.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}
