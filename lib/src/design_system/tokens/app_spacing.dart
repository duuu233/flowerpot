import 'package:flutter/widgets.dart';

/// A 4 px based spacing scale.
abstract final class AppSpacing {
  static const double none = 0;
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: xl);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
  static const EdgeInsets compactCardPadding = EdgeInsets.all(md);
  static const EdgeInsets listTilePadding = EdgeInsets.symmetric(
    horizontal: lg,
  );
}
