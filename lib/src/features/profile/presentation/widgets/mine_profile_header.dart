import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/mine_page_model.dart';

class MineProfileHeader extends StatelessWidget {
  const MineProfileHeader({
    required this.model,
    required this.onEdit,
    super.key,
  });

  final MinePageModel model;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final path = model.avatarPath;
    final imageProvider = path != null && File(path).existsSync()
        ? FileImage(File(path))
        : null;
    return Column(
      children: <Widget>[
        AppAvatar(
          size: 88,
          imageProvider: imageProvider,
          fallback: const Icon(
            Icons.person_rounded,
            size: 54,
            color: AppColors.surface,
          ),
          backgroundColor: AppColors.brandPrimary,
          onTap: onEdit,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Text(
                model.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.emptyStateTitle.copyWith(
                  fontSize: 24,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            AppIconButton(
              icon: Icons.edit_outlined,
              tooltip: '编辑个人信息',
              size: 32,
              onPressed: onEdit,
            ),
          ],
        ),
      ],
    );
  }
}
