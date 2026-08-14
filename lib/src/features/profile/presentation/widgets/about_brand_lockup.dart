import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/about_page_model.dart';

class AboutBrandLockup extends StatelessWidget {
  const AboutBrandLockup({required this.model, super.key});

  final AboutPageModel model;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('about-brand-lockup'),
      children: <Widget>[
        Image.asset(
          AppAssets.appLogo,
          key: const Key('about-logo'),
          width: 60,
          height: 60,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: 'YSplanter 应用图标',
        ),
        const SizedBox(height: AppSpacing.xl),
        Image.asset(
          AppAssets.ysplanterWordmark,
          width: 170,
          height: 36,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: model.appName,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          model.tagline,
          style: AppTypography.status.copyWith(
            color: AppColors.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
