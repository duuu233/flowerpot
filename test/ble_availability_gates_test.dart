import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// BLE 扫描的每一道门都要判到（2026-09-11 真机「搜索不到设备」之后补的）。
///
/// 少判任何一条的后果都一样：扫描**静默返回空**，而页面上显示的是「附近没有设备」
/// ——把「我们这边没配好」说成了「设备有问题」，排查方向正好反了。
void main() {
  const ok = BleAvailability(available: true, supported: true, enabled: true);

  test('全开才算可用', () {
    expect(ok.usable, isTrue);
  });

  test('任何一道门关着都不算可用', () {
    final gates = <String, BleAvailability>{
      '包里没有蓝牙模块': const BleAvailability(
        available: false,
        supported: true,
        enabled: true,
      ),
      '手机没有 BLE 硬件': const BleAvailability(
        available: true,
        supported: false,
        enabled: true,
      ),
      '蓝牙开关关着': const BleAvailability(
        available: true,
        supported: true,
        enabled: false,
      ),
      // 下面三条是这一轮补上的，也是最容易漏判、最容易被误判成"设备有问题"的三条。
      '系统定位服务关着': const BleAvailability(
        available: true,
        supported: true,
        enabled: true,
        locationOn: false,
      ),
      '没有附近设备权限': const BleAvailability(
        available: true,
        supported: true,
        enabled: true,
        scanPermission: false,
      ),
      '没有定位权限': const BleAvailability(
        available: true,
        supported: true,
        enabled: true,
        locationPermission: false,
      ),
    };
    gates.forEach((name, availability) {
      expect(availability.usable, isFalse, reason: '$name 时不该判成可用');
    });
  });

  test('老桥接不回新字段时按"没问题"处理，别凭空报一个定位没开', () {
    // 三个新字段缺省为 true：桥接还没升级的机器上，不应该因为读不到就
    // 报「定位服务关着」把人带偏。
    final legacy = BleAvailability.fromMap(const <Object?, Object?>{
      'available': true,
      'supported': true,
      'enabled': true,
    });
    expect(legacy.usable, isTrue);
    expect(legacy.locationOn, isTrue);
    expect(legacy.scanPermission, isTrue);
    expect(legacy.locationPermission, isTrue);
  });

  test('桥接明确回 false 时要认出来', () {
    final blocked = BleAvailability.fromMap(const <Object?, Object?>{
      'available': true,
      'supported': true,
      'enabled': true,
      'locationOn': false,
      'reason': '系统定位服务没打开（BLE 扫描需要，关着会静默扫不到）',
    });
    expect(blocked.usable, isFalse);
    expect(blocked.locationOn, isFalse);
    expect(blocked.reason, contains('定位服务'));
  });
}
