import 'dart:ui';

import 'package:flutter/material.dart';

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
        decoration: BoxDecoration(gradient: background.gradient),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (background != AppPageBackground.plain) ...<Widget>[
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
  warm,
  plain;

  LinearGradient get gradient => switch (this) {
    standard => const LinearGradient(
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
