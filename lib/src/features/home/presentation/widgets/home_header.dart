import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.userLabel,
    super.key,
    this.avatarImage,
    this.onAvatarTap,
    this.onBack,
  });

  final String userLabel;
  final ImageProvider<Object>? avatarImage;

  /// Opens the profile centre. Ignored when [onBack] is set.
  final VoidCallback? onAvatarTap;

  /// When set the header shows a back button instead of the profile entry,
  /// which is what pushed device pages need.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: onBack != null
                ? _HeaderBackButton(onPressed: onBack!)
                : Semantics(
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

/// Back control sized to the 34px header row.
///
/// [AppBackButton] is an [IconButton] with a 48px minimum, which does not fit
/// beside the 32px avatar it replaces here.
class _HeaderBackButton extends StatelessWidget {
  const _HeaderBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      child: InkWell(
        key: const Key('home-back-button'),
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 32,
          child: Center(
            child: Image.asset(
              AppAssets.chevronLeftIcon,
              width: 16,
              height: 16,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        ),
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
      width: 106,
      height: 23,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'YSplanter',
    );
  }
}
