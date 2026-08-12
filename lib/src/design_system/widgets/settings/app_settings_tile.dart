import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';
import '../navigation/app_trailing_chevron.dart';

class AppSettingsTile extends StatelessWidget {
  const AppSettingsTile({
    required this.title,
    super.key,
    this.icon,
    this.leading,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.minTileHeight = 52,
    this.contentPadding = AppSpacing.listTilePadding,
    this.titleStyle,
  });

  final String title;
  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final double minTileHeight;
  final EdgeInsetsGeometry contentPadding;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary;
    return ListTile(
      minTileHeight: minTileHeight,
      contentPadding: contentPadding,
      leading:
          leading ??
          (icon == null
              ? null
              : Icon(
                  icon,
                  size: 22,
                  color: danger ? AppColors.danger : AppColors.brandPrimary,
                )),
      title: Text(
        title,
        style:
            titleStyle ??
            Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing:
          trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (value != null)
                Text(value!, style: Theme.of(context).textTheme.bodyMedium),
              if (onTap != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                const AppTrailingChevron(),
              ],
            ],
          ),
      onTap: onTap,
    );
  }
}
