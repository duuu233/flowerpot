import 'package:flutter/material.dart';

import '../../tokens/app_spacing.dart';
import 'app_back_button.dart';

/// 二级页标题栏。
///
/// 尺寸按 Figma（375×812，状态栏 44）：返回箭头与标题中心都在 y=67，即状态栏下 23 →
/// 栏高 [height] = 46（原 Material 默认 56，标题低 5、正文整体从 y=100 起，比稿子低约 20）；
/// 返回箭头中心 x≈41（原 28，贴左偏 13）→ 返回键那一格宽 [backLeadingWidth]，IconButton 居中。
/// 各页顶部内边距按「稿子里首块内容的 y − 90」取。
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

  static const double height = 46;
  static const double backLeadingWidth = 82;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final resolvedLeading =
        leading ??
        (automaticallyImplyLeading && canPop
            ? AppBackButton(
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              )
            : null);
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: height,
      // 只有返回键按稿子往里挪；别的 leading（如设备列表的头像）保持原位。
      leadingWidth: resolvedLeading is AppBackButton ? backLeadingWidth : null,
      leading: resolvedLeading,
      title: Text(title),
      actions: actions == null
          ? null
          : <Widget>[...actions!, const SizedBox(width: AppSpacing.sm)],
    );
  }
}
