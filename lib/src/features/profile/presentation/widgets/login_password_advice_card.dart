import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/login_password_page_model.dart';

class LoginPasswordAdviceCard extends StatelessWidget {
  const LoginPasswordAdviceCard({required this.model, super.key});

  final LoginPasswordPageModel model;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      color: AppColors.brandSurfaceAlt,
      borderRadius: AppRadius.large,
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 18),
      showShadow: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.contact_support_rounded,
            size: 26,
            color: AppColors.brandPrimary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '密码设置建议',
                  style: AppTypography.sectionTitle.copyWith(
                    color: AppColors.brandPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 7),
                Text('1. ${model.lengthAdvice}', style: _adviceStyle),
                const SizedBox(height: 4),
                Text('2. 建议包含字母和数字的组合', style: _adviceStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _adviceStyle => AppTypography.compactBody.copyWith(
    color: AppColors.textSecondary,
    fontSize: 13,
    height: 1.35,
  );
}
