import 'package:flutter/material.dart';

import '../../tokens/app_spacing.dart';
import 'app_back_button.dart';

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
              ? AppBackButton(
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                )
              : null),
      title: Text(title),
      actions: actions == null
          ? null
          : <Widget>[...actions!, const SizedBox(width: AppSpacing.sm)],
    );
  }
}
