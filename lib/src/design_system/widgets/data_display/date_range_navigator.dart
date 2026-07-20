import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

class DateRangeNavigator extends StatelessWidget {
  const DateRangeNavigator({
    required this.label,
    super.key,
    this.onPrevious,
    this.onNext,
    this.onLabelTap,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onLabelTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        _NavigationButton(
          icon: Icons.chevron_left_rounded,
          onPressed: onPrevious,
        ),
        if (onLabelTap == null)
          Text(label, style: Theme.of(context).textTheme.bodyLarge)
        else
          TextButton.icon(
            onPressed: onLabelTap,
            label: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            iconAlignment: IconAlignment.end,
            icon: const Icon(
              Icons.arrow_drop_down_rounded,
              color: AppColors.textPrimary,
            ),
          ),
        _NavigationButton(icon: Icons.chevron_right_rounded, onPressed: onNext),
      ],
    );
  }
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textSecondary,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
    );
  }
}
