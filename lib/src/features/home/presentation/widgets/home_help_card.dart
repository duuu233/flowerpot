import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class HomeHelpCard extends StatelessWidget {
  const HomeHelpCard({required this.topics, required this.onTap, super.key});

  final List<String> topics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 92),
      child: AppSurfaceCard(
        onTap: onTap,
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
              size: 24,
              iconSize: 24,
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
