import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_radius.dart';
import '../../tokens/app_spacing.dart';
import '../cards/app_surface_card.dart';

class AppSettingsList extends StatelessWidget {
  const AppSettingsList({
    required this.children,
    super.key,
    this.showDividers = true,
    this.borderRadius = AppRadius.card,
    this.color = AppColors.surface,
    this.showShadow = true,
  });

  final List<Widget> children;
  final bool showDividers;
  final BorderRadius borderRadius;
  final Color color;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: borderRadius,
      color: color,
      showShadow: showShadow,
      child: Column(
        children: <Widget>[
          for (var index = 0; index < children.length; index++) ...<Widget>[
            children[index],
            if (showDividers && index < children.length - 1)
              const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}
