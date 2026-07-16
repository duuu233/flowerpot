import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.userLabel,
    required this.onAvatarTap,
    super.key,
    this.showGenericAvatar = false,
  });

  final String userLabel;
  final VoidCallback onAvatarTap;
  final bool showGenericAvatar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: AppAvatar(
              size: 32,
              fallbackText: userLabel,
              fallback: showGenericAvatar
                  ? const Icon(
                      Icons.person_rounded,
                      size: 29,
                      color: AppColors.surface,
                    )
                  : null,
              backgroundColor: showGenericAvatar
                  ? AppColors.brandPrimary
                  : AppColors.brandSurface,
              onTap: onAvatarTap,
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
    return SizedBox(
      width: 124,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          const Text(
            'YSplanter',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 23,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.8,
            ),
          ),
          Positioned(
            top: -1,
            right: 34,
            child: Transform.rotate(
              angle: -0.35,
              child: const Icon(
                Icons.eco_rounded,
                size: 11,
                color: AppColors.brandPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
