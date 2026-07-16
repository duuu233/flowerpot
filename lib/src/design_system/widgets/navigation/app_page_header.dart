import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

class AppPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppPageHeader({
    required this.title,
    super.key,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
    this.onBack,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    return AppBar(
      automaticallyImplyLeading: false,
      leading:
          leading ??
          (automaticallyImplyLeading && canPop
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                )
              : null),
      title: Text(title),
      actions: actions == null
          ? null
          : <Widget>[...actions!, const SizedBox(width: AppSpacing.sm)],
    );
  }
}
