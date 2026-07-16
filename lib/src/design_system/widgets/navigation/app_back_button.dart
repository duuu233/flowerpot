import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.color});

  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: Icon(
        Icons.arrow_back_ios_new_rounded,
        size: 18,
        color: color ?? AppColors.textSecondary,
      ),
    );
  }
}
