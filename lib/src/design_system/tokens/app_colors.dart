import 'package:flutter/material.dart';

/// Semantic color tokens derived from the YSplanter Figma source.
abstract final class AppColors {
  static const Color brandPrimary = Color(0xFF70AFB5);
  static const Color brandDark = Color(0xFF439095);
  static const Color brandSoft = Color(0xFFA7D1D5);
  static const Color brandSurface = Color(0xFFEEF6F7);
  static const Color brandSurfaceAlt = Color(0xFFECF4F5);

  static const Color canvas = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceTranslucent = Color(0xA8FFFFFF);

  static const Color textStrong = Color(0xFF000000);
  static const Color textPrimary = Color(0xFF252525);
  static const Color textSecondary = Color(0x99252525);
  static const Color textTertiary = Color(0x66252525);

  static const Color divider = Color(0xFFEAEAEA);
  static const Color disabled = Color(0xFFD1D1D6);
  static const Color outline = Color(0x33252525);

  static const Color success = Color(0xFF00B39B);
  static const Color successSurface = Color(0xFFE5F7F5);
  static const Color warning = Color(0xFFF69608);
  static const Color warningSoft = Color(0xFFFDBE4B);
  static const Color warningSurface = Color(0xFFFEF6E6);
  static const Color danger = Color(0xFFEB7275);
  static const Color dangerSurface = Color(0xFFFFF3F2);
  static const Color info = Color(0xFF4A95DA);
  static const Color infoDark = Color(0xFF1D8BA6);

  // Compatibility aliases for the existing UI during migration.
  static const Color ink = textPrimary;
  static const Color muted = textSecondary;
  static const Color leaf = brandPrimary;
  static const Color leafDark = brandDark;
  static const Color lime = brandSoft;
  static const Color cream = canvas;
  static const Color warm = warningSurface;
  static const Color water = info;
  static const Color sun = warning;
}
