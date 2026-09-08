import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/mine_page_model.dart';

class MineMenuList extends StatelessWidget {
  const MineMenuList({
    required this.items,
    required this.onItemTap,
    required this.height,
    super.key,
  });

  final List<MineMenuItem> items;
  final ValueChanged<MineMenuKind> onItemTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      // 行高抬到 61、补下划线，与「账号与安全」那张卡一致；缩进对齐 32px 内容边距。
      child: AppSettingsList(
        showShadow: false,
        dividerIndent: 32,
        dividerEndIndent: 32,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),
          for (final item in items)
            AppSettingsTile(
              title: item.label,
              value: item.trailingValue,
              minTileHeight: 61,
              contentPadding: const EdgeInsets.symmetric(horizontal: 32),
              leading: Image.asset(
                _assetFor(item.kind),
                width: 26,
                height: 26,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                semanticLabel: item.label,
              ),
              titleStyle: AppTypography.status.copyWith(fontSize: 16),
              // 意见反馈点了是复制邮箱，不是跳页，所以行尾画复制图标而不是箭头。
              trailing: item.badge
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const AppNoticeDot(semanticLabel: '有新版本'),
                        const SizedBox(width: AppSpacing.xs),
                        if (item.trailingValue != null)
                          Text(
                            item.trailingValue!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        const SizedBox(width: AppSpacing.xs),
                        const AppTrailingChevron(),
                      ],
                    )
                  : item.kind == MineMenuKind.feedback
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (item.trailingValue != null)
                          Text(
                            item.trailingValue!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                          semanticLabel: '复制邮箱',
                        ),
                      ],
                    )
                  : null,
              onTap: () => onItemTap(item.kind),
            ),
        ],
      ),
    );
  }

  String _assetFor(MineMenuKind kind) => switch (kind) {
    MineMenuKind.personalInfo => AppAssets.profileMenuPersonalInfoIcon,
    MineMenuKind.accountSecurity => AppAssets.profileMenuAccountSecurityIcon,
    MineMenuKind.deviceSettings => AppAssets.deviceSettingsIcon,
    MineMenuKind.feedback => AppAssets.profileMenuFeedbackIcon,
    MineMenuKind.privacyPolicy => AppAssets.profileMenuPrivacyIcon,
    MineMenuKind.userAgreement => AppAssets.profileMenuAgreementIcon,
    MineMenuKind.about => AppAssets.profileMenuAboutIcon,
  };
}
