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
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      // 行高抬到 61、补下划线，与「账号与安全」那张卡一致；缩进对齐 32px 内容边距。
      // 分隔线自己画（2026-09-23 产品：「去掉个人信息上面的横线，然后在底部放一个横线」）：
      // 列表组件是在**相邻两项之间**插线，顶上那段留白也算一项，于是「个人信息」上面多一条、
      // 最后一项下面没有。这里关掉它的自动分隔，改成每一项下面各一条。
      child: AppSettingsList(
        showShadow: false,
        showDividers: false,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        children: <Widget>[
          const SizedBox(height: AppSpacing.sm),
          for (final item in items) ...<Widget>[
            AppSettingsTile(
              title: item.label,
              value: item.kind == MineMenuKind.feedback ? null : item.trailingValue,
              subtitle: item.kind == MineMenuKind.feedback ? item.trailingValue : null,
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
                  ? const Icon(Icons.copy_rounded, size: 18,
                      color: AppColors.textSecondary, semanticLabel: '复制邮箱')
                  : null,
              onTap: () => onItemTap(item.kind),
            ),
            const Divider(height: 1, indent: 32, endIndent: 32),
          ],
        ],
      ),
    );
  }

  String _assetFor(MineMenuKind kind) => switch (kind) {
    MineMenuKind.personalInfo => AppAssets.profileMenuPersonalInfoIcon,
    MineMenuKind.accountSecurity => AppAssets.profileMenuAccountSecurityIcon,
    MineMenuKind.feedback => AppAssets.profileMenuFeedbackIcon,
    MineMenuKind.privacyPolicy => AppAssets.profileMenuPrivacyIcon,
    MineMenuKind.userAgreement => AppAssets.profileMenuAgreementIcon,
    MineMenuKind.about => AppAssets.profileMenuAboutIcon,
  };
}
