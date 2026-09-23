import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';

/// Standard trailing affordance for tappable left-content/right-action rows.
class AppTrailingChevron extends StatelessWidget {
  const AppTrailingChevron({super.key, this.size = dimension});

  static const double dimension = 14;

  /// 默认 14；个别稿子上是 16（首页快捷项，2026-09-23 按 Figma 核对）。
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.chevronRightIcon,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }
}
