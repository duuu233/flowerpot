import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.imageProvider,
    this.fallbackText,
    this.fallback,
    this.backgroundColor = AppColors.brandSurface,
    this.size = 56,
    this.onTap,
  });

  final ImageProvider<Object>? imageProvider;
  final String? fallbackText;
  final Widget? fallback;
  final Color backgroundColor;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: backgroundColor,
      foregroundImage: imageProvider,
      child: imageProvider == null
          ? fallback ??
                Text(
                  _initials(fallbackText),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: AppColors.brandDark),
                )
          : null,
    );
    if (onTap == null) return avatar;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: avatar,
    );
  }

  String _initials(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '?';
    return text.characters.first.toUpperCase();
  }
}
