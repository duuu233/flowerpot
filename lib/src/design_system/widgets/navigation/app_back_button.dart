import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.color});

  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: Image.asset(
        AppAssets.chevronLeftIcon,
        width: 18,
        height: 18,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        excludeFromSemantics: true,
      ),
    );
  }
}
