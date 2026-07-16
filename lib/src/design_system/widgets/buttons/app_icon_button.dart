import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

enum AppIconButtonStyle { plain, filled, outlined }

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    super.key,
    this.onPressed,
    this.style = AppIconButtonStyle.plain,
    this.color = AppColors.brandPrimary,
    this.size = 40,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final AppIconButtonStyle style;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = switch (style) {
      AppIconButtonStyle.plain => IconButton.styleFrom(foregroundColor: color),
      AppIconButtonStyle.filled => IconButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: .12),
      ),
      AppIconButtonStyle.outlined => IconButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: .45)),
      ),
    };
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        style: buttonStyle,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
