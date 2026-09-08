import '../../../tuya/tuya_models.dart';

enum DeviceSettingsMenuKind {
  plant,
  plantDetection,
  display,
  led,
  hearing,
  touch,
  vibration,
  behavior,
  memorial,
  other,
}

class DeviceSettingsMenuItem {
  const DeviceSettingsMenuItem({
    required this.kind,
    required this.label,
    this.value,
    this.badge = false,
  });

  final DeviceSettingsMenuKind kind;
  final String label;
  final String? value;

  /// 行尾的小红点。「其他设置」在有待装固件时点亮，用户不必先点进去才知道。
  final bool badge;
}

class DeviceSettingsPageModel {
  const DeviceSettingsPageModel({
    required this.deviceId,
    required this.deviceName,
    required this.plantName,
    required this.companionDays,
    required this.menuItems,
  });

  /// [firmwareUpdate] 来自 `FlowerpotState.hasFirmwareUpdate`：涂鸦说有新固件
  /// 可装。固件本身藏在「其他设置」里，所以这里只把红点带到那一行。
  factory DeviceSettingsPageModel.fromDevice(
    SmartPlanterDevice device, {
    bool firmwareUpdate = false,
  }) {
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
          kind: DeviceSettingsMenuKind.plantDetection,
          label: '自动检测植物',
          // 和 LED 设置同款：这一行只显示状态，开关放在自己的页面里。
          value: settings.plantDetection ? '已开启' : '已关闭',
        ),
        DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.display,
          label: '显示',
          value: settings.autoBrightness ? '自动' : '手动',
        ),
        DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.led,
          label: 'LED设置',
          // 与「显示」共用 DP 117，见 LedSettingsPageModel。
          value: settings.autoBrightness ? '已开启' : '已关闭',
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
        // The design leaves these rows with a chevron and no value.
        const DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.behavior,
          label: '行为',
        ),
        const DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.memorial,
          label: '纪念日',
        ),
        DeviceSettingsMenuItem(
          kind: DeviceSettingsMenuKind.other,
          label: '其他设置',
          badge: firmwareUpdate,
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
