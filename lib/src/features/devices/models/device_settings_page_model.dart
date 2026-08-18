import '../../../tuya/tuya_models.dart';

enum DeviceSettingsMenuKind {
  plant,
  display,
  hearing,
  touch,
  vibration,
  behavior,
  other,
}

class DeviceSettingsMenuItem {
  const DeviceSettingsMenuItem({
    required this.kind,
    required this.label,
    this.value,
  });

  final DeviceSettingsMenuKind kind;
  final String label;
  final String? value;
}

class DeviceSettingsPageModel {
  const DeviceSettingsPageModel({
    required this.deviceId,
    required this.deviceName,
    required this.plantName,
    required this.companionDays,
    required this.menuItems,
  });

  factory DeviceSettingsPageModel.fromDevice(SmartPlanterDevice device) {
    final settings = device.settings;
    return DeviceSettingsPageModel(
      deviceId: device.id,
      deviceName: device.name,
      plantName: device.plant.name,
      companionDays: device.companionDays,
      menuItems: <DeviceSettingsMenuItem>[
        DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.plant,
          label: '选择植物',
          value: device.plant.name,
        ),
        DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.display,
          label: '显示',
          value: settings.autoBrightness ? '自动' : '手动',
        ),
        DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.hearing,
          label: '听觉感知',
          value: settings.soundInteraction ? '已开启' : '已关闭',
        ),
        DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.touch,
          label: '触觉感知',
          value: settings.touchInteraction ? '已启用' : '已禁用',
        ),
        DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.vibration,
          label: '震动设置',
          value: settings.vibration ? '已启用' : '已禁用',
        ),
        // The design leaves these two rows with a chevron and no value.
        const DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.behavior,
          label: '行为',
        ),
        const DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.other,
          label: '其他设置',
        ),
      ],
    );
  }

  final String deviceId;
  final String deviceName;
  final String plantName;
  final int companionDays;
  final List<DeviceSettingsMenuItem> menuItems;
}
