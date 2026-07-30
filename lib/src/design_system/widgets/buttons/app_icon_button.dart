import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

enum AppIconButtonStyle { plain, filled, outlined }

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.tooltip,
    super.key,
    this.icon,
    this.assetPath,
    this.onPressed,
    this.style = AppIconButtonStyle.plain,
    this.color = AppColors.brandPrimary,
    this.size = 40,
  }) : assert(icon != null || assetPath != null),
       assert(icon == null || assetPath == null);

  final IconData? icon;
  final String? assetPath;
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
        icon: assetPath == null
            ? Icon(icon, size: 20)
            : Image.asset(
                assetPath!,
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
      ),
    );
  }
}
