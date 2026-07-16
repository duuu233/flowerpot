import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const String fontFamily = 'Source Han Sans CN VF';
  static const List<String> fontFallback = <String>[
    'Source Han Sans CN',
    'Noto Sans CJK SC',
    'PingFang SC',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static const TextStyle axis = TextStyle(
    color: AppColors.textSecondary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle smallBody = TextStyle(
    color: AppColors.textSecondary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.58,
  );

  static const TextStyle compactBody = TextStyle(
    color: AppColors.textSecondary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle body = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle bodyEmphasis = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  static const TextStyle sectionTitle = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const TextStyle status = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const TextStyle pageTitle = TextStyle(
    color: AppColors.textStrong,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  static const TextStyle deviceTitle = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.47,
  );

  static const TextStyle emptyStateTitle = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static const TextTheme textTheme = TextTheme(
    displaySmall: TextStyle(
      color: AppColors.textStrong,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      fontSize: 32,
      fontWeight: FontWeight.w500,
      height: 1.2,
    ),
    headlineMedium: emptyStateTitle,
    headlineSmall: deviceTitle,
    titleLarge: pageTitle,
    titleMedium: sectionTitle,
    titleSmall: bodyEmphasis,
    bodyLarge: body,
    bodyMedium: compactBody,
    bodySmall: smallBody,
    labelLarge: bodyEmphasis,
    labelMedium: compactBody,
    labelSmall: axis,
  );
}
