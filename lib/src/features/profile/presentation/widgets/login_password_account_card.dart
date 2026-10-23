import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/login_password_page_model.dart';

class LoginPasswordAccountCard extends StatelessWidget {
  const LoginPasswordAccountCard({required this.model, super.key});

  final LoginPasswordPageModel model;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      padding: const EdgeInsets.fromLTRB(22, 13, 18, 13),
      showShadow: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Row(
          children: <Widget>[
            const AppIconBadge(
              assetPath: AppAssets.accountPasswordHeaderIcon,
              semanticLabel: '登录密码',
              backgroundColor: Colors.transparent,
              size: 40,
              iconSize: 40,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '设置登录密码后，可使用“手机号+密码”\n登录东方金穗账号',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      height: 1.45,
                      letterSpacing: -.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '当前账号： ${model.maskedAccount}',
                    style: AppTypography.compactBody.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
