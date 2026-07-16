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
      child: AppSettingsList(
        showDividers: false,
        showShadow: false,
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
              minTileHeight: 48,
              contentPadding: const EdgeInsets.symmetric(horizontal: 32),
              leading: Icon(
                _iconFor(item.kind),
                size: 26,
                color: AppColors.brandPrimary,
              ),
              titleStyle: AppTypography.status.copyWith(fontSize: 16),
              onTap: () => onItemTap(item.kind),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(MineMenuKind kind) => switch (kind) {
    MineMenuKind.personalInfo => Icons.manage_accounts_outlined,
    MineMenuKind.accountSecurity => Icons.shield_outlined,
    MineMenuKind.helpCenter => Icons.help_outline_rounded,
    MineMenuKind.feedback => Icons.rate_review_outlined,
    MineMenuKind.privacyPolicy => Icons.verified_user_outlined,
    MineMenuKind.userAgreement => Icons.description_outlined,
    MineMenuKind.about => Icons.info_outline_rounded,
  };
}
