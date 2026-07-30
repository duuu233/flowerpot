import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/personal_info_page_model.dart';

class PersonalInfoCard extends StatelessWidget {
  const PersonalInfoCard({
    required this.model,
    required this.onAvatarTap,
    required this.onNicknameTap,
    required this.onPhoneTap,
    required this.onAccountIdTap,
    super.key,
    this.avatarImage,
  });

  final PersonalInfoPageModel model;
  final ImageProvider<Object>? avatarImage;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onNicknameTap;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onAccountIdTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('personal-info-card'),
      padding: EdgeInsets.zero,
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      showShadow: false,
      child: Column(
        children: <Widget>[
          _PersonalInfoRow(
            rowKey: const Key('personal-info-avatar'),
            label: '头像',
            onTap: onAvatarTap,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppAvatar(
                  size: 36,
                  imageProvider: avatarImage,
                  fallbackText: model.nickname,
                  fallback: Image.asset(
                    AppAssets.profileAvatarIcon,
                    width: 36,
                    height: 36,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  backgroundColor: AppColors.brandSurface,
                ),
                const SizedBox(width: AppSpacing.sm),
                const _TrailingChevron(),
              ],
            ),
          ),
          const _PersonalInfoDivider(),
          _PersonalInfoRow(
            rowKey: const Key('personal-info-nickname'),
            label: '昵称',
            onTap: onNicknameTap,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _PersonalInfoValue(model.nickname),
                const SizedBox(width: AppSpacing.sm),
                Image.asset(
                  AppAssets.profileEditIcon,
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
              ],
            ),
          ),
          const _PersonalInfoDivider(),
          _PersonalInfoRow(
            rowKey: const Key('personal-info-phone'),
            label: '手机号',
            onTap: onPhoneTap,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _PersonalInfoValue(model.phone),
                const SizedBox(width: AppSpacing.sm),
                const _TrailingChevron(),
              ],
            ),
          ),
          const _PersonalInfoDivider(),
          _PersonalInfoRow(
            rowKey: const Key('personal-info-account-id'),
            label: '账号ID',
            onTap: onAccountIdTap,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _PersonalInfoValue(model.accountId),
                const SizedBox(width: AppSpacing.sm),
                const _TrailingChevron(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PersonalInfoLogoutButton extends StatelessWidget {
  const PersonalInfoLogoutButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: const Key('personal-info-logout'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandPrimary,
        disabledForegroundColor: AppColors.disabled,
        minimumSize: const Size(140, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      ),
      onPressed: onPressed,
      child: Text(
        '退出登录',
        style: AppTypography.pageTitle.copyWith(
          color: onPressed == null
              ? AppColors.disabled
              : AppColors.brandPrimary,
          fontWeight: FontWeight.w400,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _PersonalInfoRow extends StatelessWidget {
  const _PersonalInfoRow({
    required this.rowKey,
    required this.label,
    required this.trailing,
    required this.onTap,
  });

  final Key rowKey;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        child: SizedBox(
          height: 61,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.sectionTitle.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalInfoValue extends StatelessWidget {
  const _PersonalInfoValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.status.copyWith(
          color: AppColors.textSecondary,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _TrailingChevron extends StatelessWidget {
  const _TrailingChevron();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.chevronRightIcon,
      width: 20,
      height: 20,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
  }
}

class _PersonalInfoDivider extends StatelessWidget {
  const _PersonalInfoDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: AppSpacing.xxl,
      endIndent: AppSpacing.xxl,
      color: AppColors.divider,
    );
  }
}
