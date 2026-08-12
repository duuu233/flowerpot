import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';

/// Standard trailing affordance for tappable left-content/right-action rows.
class AppTrailingChevron extends StatelessWidget {
  const AppTrailingChevron({super.key});

  static const double dimension = 14;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.chevronRightIcon,
      width: dimension,
      height: dimension,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }
}
