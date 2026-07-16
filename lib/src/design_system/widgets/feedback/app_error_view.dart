import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import 'app_empty_state.dart';

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    required this.message,
    super.key,
    this.title = '出现了一点问题',
    this.retryLabel = '重试',
    this.onRetry,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: title,
      message: message,
      illustration: const Icon(
        Icons.error_outline_rounded,
        size: 64,
        color: AppColors.danger,
      ),
      actionLabel: onRetry == null ? null : retryLabel,
      onAction: onRetry,
    );
  }
}
