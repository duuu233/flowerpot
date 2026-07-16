import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/device_settings_page_model.dart';

class DeviceSettingsFunctionList extends StatelessWidget {
  const DeviceSettingsFunctionList({
    required this.items,
    required this.onItemTap,
    super.key,
  });

  final List<DeviceSettingsMenuItem> items;
  final ValueChanged<DeviceSettingsMenuKind> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(width: 4, height: 18, color: AppColors.brandPrimary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '功能设置',
              style: AppTypography.pageTitle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsList(
          showDividers: false,
          borderRadius: AppRadius.large,
          children: <Widget>[
            for (final item in items)
              AppSettingsTile(
                title: item.label,
                value: item.value,
                minTileHeight: 46,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: Icon(
                  _iconFor(item.kind),
                  size: 25,
                  color: AppColors.brandPrimary,
                ),
                titleStyle: AppTypography.sectionTitle.copyWith(fontSize: 15),
                onTap: () => onItemTap(item.kind),
              ),
          ],
        ),
      ],
    );
  }

  IconData _iconFor(DeviceSettingsMenuKind kind) => switch (kind) {
    DeviceSettingsMenuKind.plant => Icons.eco_outlined,
    DeviceSettingsMenuKind.display => Icons.light_mode_outlined,
    DeviceSettingsMenuKind.hearing => Icons.hearing_rounded,
    DeviceSettingsMenuKind.touch => Icons.touch_app_outlined,
    DeviceSettingsMenuKind.vibration => Icons.vibration_rounded,
    DeviceSettingsMenuKind.behavior => Icons.manage_search_rounded,
    DeviceSettingsMenuKind.other => Icons.tune_rounded,
  };
}
