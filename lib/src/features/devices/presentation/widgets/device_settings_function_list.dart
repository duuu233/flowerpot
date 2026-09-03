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
                leading: _LeadingIcon(kind: item.kind, label: item.label),
                titleStyle: AppTypography.sectionTitle.copyWith(fontSize: 15),
                onTap: () => onItemTap(item.kind),
              ),
          ],
        ),
      ],
    );
  }

}

/// 行首的小图标。
///
/// 老的七项都有切图；LED 设置和纪念日是 v2 才加的，Figma 还没给图，用同尺寸的
/// Material 图标顶上——留个空位或者借用别人的切图都会让这两行看起来像画错了。
class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.kind, required this.label});

  final DeviceSettingsMenuKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final asset = _assetFor(kind);
    if (asset == null) {
      return Icon(
        _iconFor(kind),
        size: 24,
        color: AppColors.brandDark,
        semanticLabel: label,
      );
    }
    return Image.asset(
      asset,
      width: 25,
      height: 25,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: label,
    );
  }

  static String? _assetFor(DeviceSettingsMenuKind kind) => switch (kind) {
    DeviceSettingsMenuKind.plant => AppAssets.settingsPlantIcon,
    DeviceSettingsMenuKind.display => AppAssets.settingsDisplayIcon,
    DeviceSettingsMenuKind.hearing => AppAssets.settingsHearingIcon,
    DeviceSettingsMenuKind.touch => AppAssets.settingsTouchIcon,
    DeviceSettingsMenuKind.vibration => AppAssets.settingsVibrationIcon,
    DeviceSettingsMenuKind.behavior => AppAssets.settingsBehaviorIcon,
    DeviceSettingsMenuKind.other => AppAssets.settingsOtherIcon,
    DeviceSettingsMenuKind.led || DeviceSettingsMenuKind.memorial => null,
  };

  static IconData _iconFor(DeviceSettingsMenuKind kind) => switch (kind) {
    DeviceSettingsMenuKind.memorial => Icons.event_note_outlined,
    _ => Icons.lightbulb_outline,
  };
}
