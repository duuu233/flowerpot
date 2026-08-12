import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';
import '../cards/app_surface_card.dart';
import '../navigation/app_trailing_chevron.dart';
import 'app_icon_badge.dart';

class AppMetricTile extends StatelessWidget {
  const AppMetricTile({
    required this.title,
    required this.value,
    required this.icon,
    super.key,
    this.status,
    this.color = AppColors.brandPrimary,
    this.onTap,
  });

  final String title;
  final String value;
  final String? status;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      onTap: onTap,
      padding: AppSpacing.compactCardPadding,
      child: Row(
        children: <Widget>[
          AppIconBadge(icon: icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
                if (status != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    status!,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) const AppTrailingChevron(),
        ],
      ),
    );
  }
}
