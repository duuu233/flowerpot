import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'setting_orbit_illustration.dart';

class DeviceToggleSettingsCard extends StatelessWidget {
  const DeviceToggleSettingsCard({
    required this.symbol,
    required this.title,
    required this.status,
    required this.description,
    required this.descriptionLines,
    required this.value,
    required this.switchKey,
    required this.onChanged,
    super.key,
    this.updating = false,
  });

  final DeviceSettingSymbol symbol;
  final String title;
  final String status;
  final String description;
  final List<String> descriptionLines;
  final bool value;
  final Key switchKey;
  final ValueChanged<bool>? onChanged;
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
            height: 184,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(
                top: DeviceSettingOrbitIllustration.topInset,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: DeviceSettingOrbitIllustration(symbol: symbol),
              ),
            ),
          ),
          SizedBox(
            height: 68,
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
                          title,
                          style: AppTypography.sectionTitle.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            // 标题不再加粗（LED 设置提的，震动/触觉/自动检测植物
                            // 共用这张卡，一起跟着改）。
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status,
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
                      value: value,
                      onChanged: updating ? null : onChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(indent: 22, endIndent: 22),
          SizedBox(
            height: 86,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 19, 22, 29),
              child: Semantics(
                label: description,
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final line in descriptionLines)
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
          ),
        ],
      ),
    );
  }
}
