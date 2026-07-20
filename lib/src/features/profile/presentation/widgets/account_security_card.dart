import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/account_security_page_model.dart';

class AccountSecurityCard extends StatelessWidget {
  const AccountSecurityCard({
    required this.model,
    required this.onPhoneTap,
    required this.onLoginPasswordTap,
    required this.onChangePasswordTap,
    required this.onForgotPasswordTap,
    super.key,
  });

  final AccountSecurityPageModel model;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onLoginPasswordTap;
  final VoidCallback? onChangePasswordTap;
  final VoidCallback? onForgotPasswordTap;

  @override
  Widget build(BuildContext context) {
    return AppSettingsList(
      key: const Key('account-security-card'),
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      showShadow: false,
      dividerIndent: AppSpacing.xxl,
      dividerEndIndent: AppSpacing.xxl,
      children: <Widget>[
        _AccountSecurityTile(
          tileKey: const Key('account-security-phone'),
          label: '手机号',
          value: model.phone,
          onTap: onPhoneTap,
        ),
        _AccountSecurityTile(
          tileKey: const Key('account-security-login-password'),
          label: '登录密码',
          value: model.passwordStatus,
          onTap: onLoginPasswordTap,
        ),
        _AccountSecurityTile(
          tileKey: const Key('account-security-change-password'),
          label: '修改密码',
          onTap: onChangePasswordTap,
        ),
        _AccountSecurityTile(
          tileKey: const Key('account-security-forgot-password'),
          label: '忘记密码',
          value: model.forgotPasswordHint,
          onTap: onForgotPasswordTap,
        ),
      ],
    );
  }
}

class _AccountSecurityTile extends StatelessWidget {
  const _AccountSecurityTile({
    required this.tileKey,
    required this.label,
    required this.onTap,
    this.value,
  });

  final Key tileKey;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppSettingsTile(
      key: tileKey,
      title: label,
      minTileHeight: 61,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      titleStyle: AppTypography.sectionTitle.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.status.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.textSecondary,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
