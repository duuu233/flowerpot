import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

/// 圆形头像。
///
/// 传了 [imageProvider] 但**加载失败**时（换了账号、URL 失效、离线），要退回
/// [fallback]：`CircleAvatar` 的 `child` 只在没有 foregroundImage 时显示，加载
/// 失败它只剩一个空底色——设备列表左上角那个「我的」入口就是这样「消失」的。
class AppAvatar extends StatefulWidget {
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
  State<AppAvatar> createState() => _AppAvatarState();

  static String initials(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '?';
    return text.characters.first.toUpperCase();
  }
}

class _AppAvatarState extends State<AppAvatar> {
  /// 当前这张图加载失败了：按没有图处理，直到换成另一张图为止。
  bool _failed = false;

  @override
  void didUpdateWidget(AppAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageProvider != oldWidget.imageProvider) _failed = false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _failed ? null : widget.imageProvider;
    final avatar = CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: widget.backgroundColor,
      foregroundImage: provider,
      onForegroundImageError: provider == null
          ? null
          : (_, _) {
              if (mounted) setState(() => _failed = true);
            },
      child: provider == null
          ? widget.fallback ??
                Text(
                  AppAvatar.initials(widget.fallbackText),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: AppColors.brandDark),
                )
          : null,
    );
    if (widget.onTap == null) return avatar;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: widget.onTap,
      child: avatar,
    );
  }
}
