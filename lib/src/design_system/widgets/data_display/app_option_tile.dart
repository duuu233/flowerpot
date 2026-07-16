import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';

class AppOptionTile extends StatelessWidget {
  const AppOptionTile({
    required this.label,
    required this.selected,
    super.key,
    this.subtitle,
    this.leading,
    this.onTap,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandSurface : Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      child: ListTile(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
        leading: leading,
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: selected
              ? const Icon(
                  Icons.check_circle_rounded,
                  key: ValueKey<bool>(true),
                  color: AppColors.brandPrimary,
                )
              : const Icon(
                  Icons.radio_button_unchecked_rounded,
                  key: ValueKey<bool>(false),
                  color: AppColors.disabled,
                ),
        ),
        onTap: onTap,
      ),
    );
  }
}
