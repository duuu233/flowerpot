import 'dart:ui';

import 'package:flutter/material.dart';

import '../../tokens/app_assets.dart';
import '../../tokens/app_colors.dart';

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    required this.body,
    super.key,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset,
    this.useSafeArea = true,
    this.background = AppPageBackground.standard,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool? resizeToAvoidBottomInset;
  final bool useSafeArea;
  final AppPageBackground background;

  @override
  Widget build(BuildContext context) {
    final content = useSafeArea ? SafeArea(child: body) : body;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: DecoratedBox(
        key: const Key('app-page-background'),
        decoration: BoxDecoration(gradient: background.gradient),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (background.assetPath != null)
              Image.asset(
                background.assetPath!,
                key: const Key('app-page-background-image'),
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              )
            // Corner glows belong to the warm variant only. On a sub-page they
            // tint the top-right and bottom-left, which the flat mint-to-white
            // frames do not have.
            else if (background == AppPageBackground.warm) ...<Widget>[
              const Positioned(
                top: -96,
                right: -72,
                child: _BackgroundGlow(size: 250, color: AppColors.brandSoft),
              ),
              const Positioned(
                bottom: 80,
                left: -110,
                child: _BackgroundGlow(
                  size: 260,
                  color: AppColors.brandPrimary,
                ),
              ),
            ],
            content,
          ],
        ),
      ),
    );
  }
}

enum AppPageBackground {
  standard,
  home,
  account,
  warm,
  plain,
  white;

  /// Only the home screen carries the orbit artwork. Sub-pages used to render
  /// it too, which put the ring and its pedestal glow behind every settings
  /// and status page.
  String? get assetPath => switch (this) {
    home => AppAssets.homeBackground,
    account => AppAssets.accountBackground,
    _ => null,
  };

  LinearGradient get gradient => switch (this) {
    // Sub-pages: a mint wash under the status bar fading to near-white, which
    // is what the Figma frames show.
    standard => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFFE7F1F2), Color(0xFFF6F8F8), AppColors.canvas],
      stops: <double>[0, .42, 1],
    ),
    home || account => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFFF8FBFB), Color(0xFFEFF7F8), AppColors.canvas],
      stops: <double>[0, .46, 1],
    ),
    warm => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        AppColors.warningSurface,
        AppColors.brandSurface,
        AppColors.canvas,
      ],
    ),
    plain => const LinearGradient(
      colors: <Color>[AppColors.canvas, AppColors.canvas],
    ),
    white => const LinearGradient(
      colors: <Color>[AppColors.surface, AppColors.surface],
    ),
  };
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .14),
        ),
        child: SizedBox.square(dimension: size),
      ),
    );
  }
}
