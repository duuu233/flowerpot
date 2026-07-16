import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';
import '../buttons/app_outlined_button.dart';
import '../buttons/app_primary_button.dart';

enum AppResultTone { success, error, info }

class AppResultView extends StatelessWidget {
  const AppResultView({
    required this.title,
    required this.message,
    super.key,
    this.tone = AppResultTone.success,
    this.illustration,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final AppResultTone tone;
  final Widget? illustration;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (tone) {
      AppResultTone.success => (
        Icons.check_circle_outline_rounded,
        AppColors.success,
      ),
      AppResultTone.error => (Icons.error_outline_rounded, AppColors.danger),
      AppResultTone.info => (Icons.info_outline_rounded, AppColors.info),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              illustration ?? Icon(icon, size: 84, color: color),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (primaryLabel != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xxxl),
                AppPrimaryButton(label: primaryLabel!, onPressed: onPrimary),
              ],
              if (secondaryLabel != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                AppOutlinedButton(
                  label: secondaryLabel!,
                  onPressed: onSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
