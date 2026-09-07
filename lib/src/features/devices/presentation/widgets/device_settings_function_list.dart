import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/device_settings_page_model.dart';

class DeviceSettingsFunctionList extends StatelessWidget {
  const DeviceSettingsFunctionList({
    required this.items,
    required this.onItemTap,
    super.key,
    this.onToggle,
    this.togglesBusy = false,
  });

  final List<DeviceSettingsMenuItem> items;
  final ValueChanged<DeviceSettingsMenuKind> onItemTap;

  /// 纯开关行的回调。行的 [DeviceSettingsMenuItem.toggle] 非空时才会用到。
  final void Function(DeviceSettingsMenuKind kind, bool value)? onToggle;

  /// 有一条开关正在下发：期间所有开关置灰，避免连点堆指令。
  final bool togglesBusy;

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
                // 默认的 trailing 只有取值和箭头，开关行和红点得自己拼一遍。
                trailing: item.toggle != null
                    ? _ToggleTrailing(
                        kind: item.kind,
                        value: item.toggle!,
                        onChanged: togglesBusy ? null : onToggle,
                      )
                    : item.badge
                    ? _BadgedTrailing(value: item.value)
                    : null,
                onTap: item.toggle != null
                    ? () {
                        if (togglesBusy) return;
                        onToggle?.call(item.kind, !item.toggle!);
                      }
                    : () => onItemTap(item.kind),
              ),
          ],
        ),
      ],
    );
  }
}

/// 行尾：纯开关。尺寸跟其他设置页里的开关一致。
class _ToggleTrailing extends StatelessWidget {
  const _ToggleTrailing({
    required this.kind,
    required this.value,
    required this.onChanged,
  });

  final DeviceSettingsMenuKind kind;
  final bool value;
  final void Function(DeviceSettingsMenuKind kind, bool value)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: .86,
      alignment: Alignment.centerRight,
      child: Switch(
        key: Key('device-settings-toggle-${kind.name}'),
        value: value,
        onChanged: onChanged == null
            ? null
            : (next) => onChanged!(kind, next),
      ),
    );
  }
}

/// 行尾：小红点 + 原本的取值和箭头。
class _BadgedTrailing extends StatelessWidget {
  const _BadgedTrailing({this.value});

  final String? value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const AppNoticeDot(semanticLabel: '有新固件'),
        const SizedBox(width: AppSpacing.xs),
        if (value != null) ...<Widget>[
          Text(value!, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: AppSpacing.xs),
        ],
        const AppTrailingChevron(),
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
    DeviceSettingsMenuKind.led ||
    DeviceSettingsMenuKind.memorial ||
    DeviceSettingsMenuKind.plantDetection => null,
  };

  static IconData _iconFor(DeviceSettingsMenuKind kind) => switch (kind) {
    DeviceSettingsMenuKind.memorial => Icons.event_note_outlined,
    DeviceSettingsMenuKind.plantDetection => Icons.eco_outlined,
    _ => Icons.lightbulb_outline,
  };
}
