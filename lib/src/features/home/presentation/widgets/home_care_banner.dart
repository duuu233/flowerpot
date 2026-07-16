import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class HomeCareBanner extends StatelessWidget {
  const HomeCareBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: AppSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        color: AppColors.surfaceTranslucent,
        borderRadius: AppRadius.large,
        side: const BorderSide(color: AppColors.surface),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.local_florist_rounded,
              size: 18,
              color: AppColors.brandPrimary,
            ),
            const SizedBox(width: AppSpacing.lg),
            Text(
              '今日养护',
              style: AppTypography.compactBody.copyWith(
                color: AppColors.brandPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  maxLines: 1,
                  style: AppTypography.compactBody.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
