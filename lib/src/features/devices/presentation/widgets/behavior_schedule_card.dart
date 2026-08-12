import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/behavior_settings_page_model.dart';

class BehaviorScheduleCard extends StatelessWidget {
  const BehaviorScheduleCard({
    required this.model,
    required this.switchKey,
    required this.startTimeKey,
    required this.endTimeKey,
    required this.onEnabledChanged,
    required this.onStartTimeTap,
    required this.onEndTimeTap,
    super.key,
    this.updating = false,
  });

  final BehaviorSchedulePageModel model;
  final Key switchKey;
  final Key startTimeKey;
  final Key endTimeKey;
  final ValueChanged<bool>? onEnabledChanged;
  final VoidCallback? onStartTimeTap;
  final VoidCallback? onEndTimeTap;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      padding: EdgeInsets.zero,
      showShadow: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 76,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          model.title,
                          style: AppTypography.sectionTitle.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          model.status,
                          style: AppTypography.sectionTitle.copyWith(
                            color: AppColors.brandPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: .86,
                    alignment: Alignment.centerRight,
                    child: Switch(
                      key: switchKey,
                      value: model.enabled,
                      onChanged: updating ? null : onEnabledChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(indent: 22, endIndent: 22),
          SizedBox(
            height: 191,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 19, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: 38,
                    child: Semantics(
                      label: model.description,
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            for (final line in model.descriptionLines)
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    line,
                                    maxLines: 1,
                                    style: AppTypography.body.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  BehaviorTimeRow(
                    key: startTimeKey,
                    label: '开始时间',
                    value: model.startLabel,
                    onTap: updating ? null : onStartTimeTap,
                  ),
                  const SizedBox(height: 10),
                  BehaviorTimeRow(
                    key: endTimeKey,
                    label: '结束时间',
                    value: model.endLabel,
                    onTap: updating ? null : onEndTimeTap,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BehaviorTimeRow extends StatelessWidget {
  const BehaviorTimeRow({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F7F7),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.sectionTitle.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: AppTypography.sectionTitle.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 6),
                const AppTrailingChevron(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
