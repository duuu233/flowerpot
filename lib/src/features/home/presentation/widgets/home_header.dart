import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.userLabel,
    required this.onAvatarTap,
    super.key,
    this.avatarImage,
  });

  final String userLabel;
  final VoidCallback onAvatarTap;
  final ImageProvider<Object>? avatarImage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              button: true,
              label: '${userLabel.trim().isEmpty ? '用户' : userLabel}的头像',
              child: AppAvatar(
                key: const Key('home-user-avatar'),
                size: 32,
                imageProvider: avatarImage,
                fallback: Image.asset(
                  AppAssets.profileAvatarIcon,
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
                backgroundColor: AppColors.brandSurface,
                onTap: onAvatarTap,
              ),
            ),
          ),
          const _YsplanterLogo(),
        ],
      ),
    );
  }
}

class _YsplanterLogo extends StatelessWidget {
  const _YsplanterLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.ysplanterWordmark,
      width: 124,
      height: 27,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'YSplanter',
    );
  }
}
