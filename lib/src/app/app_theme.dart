import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF17332B);
  static const muted = Color(0xFF72827A);
  static const leaf = Color(0xFF2F7D5D);
  static const leafDark = Color(0xFF1F5D45);
  static const lime = Color(0xFFBCE26A);
  static const cream = Color(0xFFF4F7F1);
  static const warm = Color(0xFFFFF6E8);
  static const water = Color(0xFF5AB6C8);
  static const sun = Color(0xFFF4AE45);
  static const danger = Color(0xFFE5655B);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.leaf,
    brightness: Brightness.light,
    primary: AppColors.leaf,
    secondary: AppColors.lime,
    surface: Colors.white,
    error: AppColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
    fontFamilyFallback: const <String>[
      'PingFang SC',
      'Microsoft YaHei',
      'Noto Sans CJK SC',
    ],
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: AppColors.ink,
        fontSize: 32,
        height: 1.12,
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: TextStyle(
        color: AppColors.ink,
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: AppColors.ink, fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.45),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.84),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFDDE6DE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.leaf, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE4EAE4),
      thickness: 1,
    ),
  );
}
