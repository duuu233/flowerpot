import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

enum AppMessageTone { success, error, info }

void showAppMessage(
  BuildContext context,
  String message, {
  AppMessageTone tone = AppMessageTone.success,
}) {
  final (icon, color) = switch (tone) {
    AppMessageTone.success => (Icons.check_circle_rounded, AppColors.success),
    AppMessageTone.error => (Icons.error_rounded, AppColors.danger),
    AppMessageTone.info => (Icons.info_rounded, AppColors.infoDark),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Row(
          children: <Widget>[
            Icon(icon, color: AppColors.surface),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
