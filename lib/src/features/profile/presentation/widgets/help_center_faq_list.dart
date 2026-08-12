import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/help_center_model.dart';

class HelpCenterFaqList extends StatelessWidget {
  const HelpCenterFaqList({
    required this.items,
    required this.expandedIds,
    required this.onToggle,
    super.key,
  });

  final List<HelpCenterFaqItem> items;
  final Set<String> expandedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('help-center-faq-card'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      showShadow: false,
      child: Column(
        children: <Widget>[
          for (final item in items)
            _HelpCenterFaqTile(
              key: Key('help-faq-${item.id}'),
              item: item,
              expanded: expandedIds.contains(item.id),
              onTap: () => onToggle(item.id),
            ),
        ],
      ),
    );
  }
}

class _HelpCenterFaqTile extends StatelessWidget {
  const _HelpCenterFaqTile({
    required this.item,
    required this.expanded,
    required this.onTap,
    super.key,
  });

  final HelpCenterFaqItem item;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          expanded: expanded,
          label: item.question,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('help-faq-toggle-${item.id}'),
              borderRadius: AppRadius.small,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 38),
                child: Row(
                  children: <Widget>[
                    const _HelpQuestionBubble(),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          item.question,
                          style: AppTypography.body.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? .25 : 0,
                      duration: AppDurations.fast,
                      curve: AppDurations.standardCurve,
                      child: const AppTrailingChevron(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: AppDurations.normal,
          curve: AppDurations.standardCurve,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.xxl,
                    top: AppSpacing.xxs,
                    bottom: AppSpacing.sm,
                  ),
                  child: Container(
                    key: Key('help-faq-answer-${item.id}'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: .03),
                      borderRadius: AppRadius.small,
                    ),
                    child: Text(
                      item.answer,
                      style: AppTypography.smallBody.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.58,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _HelpQuestionBubble extends StatelessWidget {
  const _HelpQuestionBubble();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Image.asset(
        AppAssets.helpChatIcon,
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
