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
    // `battery_status` (DP 104) is the device's own verdict; the 30% threshold
    // is only a fallback for a planter that has not reported it yet.
    final reported = device.status.battery;
    final charging = reported == BatteryStatus.charging || device.charging;
    final healthy = switch (reported) {
      BatteryStatus.good || BatteryStatus.charging => true,
      BatteryStatus.shortage => false,
      null => device.battery > 30,
    };
    final status = charging
        ? '充电中'
        : healthy
        ? '电量充足'
        : '电量偏低';
    final description = charging
        ? '已连接电源，建议长期连接电源使用。'
        : healthy
        ? '当前电量充足，可继续正常使用。'
        : '当前电量偏低，请及时连接电源充电。';
    return BatteryStatusPageModel(
      deviceId: device.id,
      status: status,
      description: description,
      battery: device.battery,
      charging: charging,
    );
  }

  final String deviceId;
  final String status;
  final String description;
  final int battery;
  final bool charging;
}
