import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// 首页底部的使用帮助卡：「1. 首次使用指南」等几条。
///
/// ⚠️ **纯文本，不可点**（2026-09-14 产品：去掉首次使用指南的点击跳转，只是纯文本展示）。
/// 帮助中心的入口挪到了上面快捷列表里（`HomeActionKind.help`）。
class HomeHelpCard extends StatelessWidget {
  const HomeHelpCard({required this.topics, super.key});

  final List<String> topics;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 92),
      child: AppSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.large,
        showShadow: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const AppIconBadge(
              assetPath: AppAssets.helpChatIcon,
              semanticLabel: '使用帮助',
              backgroundColor: Colors.transparent,
              // 稿子 26（2026-09-23 按 Figma 156:4304 核对，原来 24）。
              size: 26,
              iconSize: 26,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (var index = 0; index < topics.length; index++)
                    Text(
                      '${index + 1}. ${topics[index]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.smallBody.copyWith(
                        height: 1.65,
                        color: AppColors.textSecondary,
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
