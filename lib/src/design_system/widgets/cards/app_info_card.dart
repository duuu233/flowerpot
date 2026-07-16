import 'package:flutter/material.dart';

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
  });

  final String title;
  final String message;
  final IconData? icon;
  final AppInfoTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(tone);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.$2, borderRadius: AppRadius.card),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon ?? Icons.lightbulb_outline_rounded, color: colors.$1),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: colors.$1),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
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
