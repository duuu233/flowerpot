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
    this.emphasized = false,
  });

  final String title;
  final String message;
  final IconData? icon;
  final AppInfoTone tone;
  final Widget? trailing;
  final bool emphasized;

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
            if (emphasized)
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    icon ?? Icons.lightbulb_outline_rounded,
                    color: colors.$1,
                    size: 28,
                  ),
                ),
              )
            else
              Icon(icon ?? Icons.lightbulb_outline_rounded, color: colors.$1),
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
