import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';
import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';
import '../../tokens/app_spacing.dart';

enum AppInfoTone { brand, info, success, warning, danger }

class AppInfoCard extends StatelessWidget {
  const AppInfoCard({
    required this.title,
    required this.message,
    super.key,
    this.icon,
    this.tone = AppInfoTone.brand,
    this.trailing,
    this.emphasized = false,
  });

  final String title;
  final String message;
  final IconData? icon;
  final AppInfoTone tone;
  final Widget? trailing;
  final bool emphasized;

  /// The default advice mark has real artwork, so it is drawn from the asset
  /// rather than a Material glyph; callers passing an [icon] keep the glyph.
  Widget _leading(Color color, double size) {
    if (icon != null) return Icon(icon, color: color, size: size);
    return Image.asset(
      AppAssets.plantCareTipIcon,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors(tone);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.$2, borderRadius: AppRadius.card),
      child: Padding(
        // 状态页建议卡（emphasized）按 Figma 156:5082 / 156:4814：左 20、上下 11，图标与文字垂直居中
        // （原四边 16、顶对齐，卡高约 100，稿子 78）。
        padding: emphasized
            ? const EdgeInsets.fromLTRB(20, 11, 17, 11)
            : AppSpacing.cardPadding,
        child: Row(
          crossAxisAlignment: emphasized
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: <Widget>[
            if (emphasized)
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                // 圆底 40（2026-09-23 按 Figma 光照状态 156:4814 建议卡核对，原来 37）。
                child: SizedBox.square(
                  dimension: 40,
                  child: Center(child: _leading(colors.$1, 22)),
                ),
              )
            else
              _leading(colors.$1, 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: emphasized
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: colors.$1),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    message,
                    style: emphasized
                        ? Theme.of(context).textTheme.bodyMedium
                        : Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  (Color, Color) _colors(AppInfoTone value) => switch (value) {
    AppInfoTone.brand => (AppColors.brandDark, AppColors.brandSurface),
    AppInfoTone.info => (AppColors.infoDark, AppColors.brandSurface),
    AppInfoTone.success => (AppColors.success, AppColors.successSurface),
    AppInfoTone.warning => (AppColors.warning, AppColors.warningSurface),
    AppInfoTone.danger => (AppColors.danger, AppColors.dangerSurface),
  };
}
