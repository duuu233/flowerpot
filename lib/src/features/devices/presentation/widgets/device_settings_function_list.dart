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
        const SizedBox(height: AppSpacing.xs),
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
                leading: Image.asset(
                  _assetFor(item.kind),
                  width: 25,
                  height: 25,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  semanticLabel: item.label,
                ),
                titleStyle: AppTypography.sectionTitle.copyWith(fontSize: 15),
                onTap: () => onItemTap(item.kind),
              ),
          ],
        ),
      ],
    );
  }

  String _assetFor(DeviceSettingsMenuKind kind) => switch (kind) {
    DeviceSettingsMenuKind.plant => AppAssets.settingsPlantIcon,
    DeviceSettingsMenuKind.display => AppAssets.settingsDisplayIcon,
    DeviceSettingsMenuKind.hearing => AppAssets.settingsHearingIcon,
    DeviceSettingsMenuKind.touch => AppAssets.settingsTouchIcon,
    DeviceSettingsMenuKind.vibration => AppAssets.settingsVibrationIcon,
    DeviceSettingsMenuKind.behavior => AppAssets.settingsBehaviorIcon,
    DeviceSettingsMenuKind.other => AppAssets.settingsOtherIcon,
  };
}
