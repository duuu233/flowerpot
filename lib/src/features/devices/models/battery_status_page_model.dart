import '../../../tuya/tuya_models.dart';

class BatteryStatusPageModel {
  const BatteryStatusPageModel({
    required this.deviceId,
    required this.status,
    required this.description,
    required this.battery,
    required this.charging,
  });

  factory BatteryStatusPageModel.fromDevice(SmartPlanterDevice device) {
    final status = device.charging
        ? '充电中'
        : device.battery > 30
        ? '电量充足'
        : '电量偏低';
    final description = device.charging
        ? '已连接电源，建议长期连接电源使用。'
        : device.battery > 30
        ? '当前电量充足，可继续正常使用。'
        : '当前电量偏低，请及时连接电源充电。';
    return BatteryStatusPageModel(
      deviceId: device.id,
      status: status,
      description: description,
      battery: device.battery,
      charging: device.charging,
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int battery;
  final bool charging;
}
