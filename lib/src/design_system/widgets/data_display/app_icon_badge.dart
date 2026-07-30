import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';

class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    this.icon,
    this.assetPath,
    this.semanticLabel,
    this.color = AppColors.brandPrimary,
    this.backgroundColor,
    this.size = 40,
    this.iconSize = 22,
    this.borderRadius = AppRadius.full,
  }) : assert(icon != null || assetPath != null),
       assert(icon == null || assetPath == null);

  final IconData? icon;
  final String? assetPath;
  final String? semanticLabel;
  final Color color;
  final Color? backgroundColor;
  final double size;
  final double iconSize;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: .12),
        borderRadius: borderRadius,
      ),
      child: SizedBox.square(
        dimension: size,
        child: assetPath == null
            ? Icon(icon, color: color, size: iconSize)
            : Center(
                child: Image.asset(
                  assetPath!,
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  semanticLabel: semanticLabel,
                  excludeFromSemantics: semanticLabel == null,
                ),
              ),
      ),
    );
  }
}
