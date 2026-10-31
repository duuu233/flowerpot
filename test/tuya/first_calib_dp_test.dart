import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _methodChannel = 'test/tuya_first_calib';
const _eventChannel = 'test/tuya_first_calib_events';

Map<Object?, Object?> _deviceMap(String id, Map<Object?, Object?> dps) =>
    <Object?, Object?>{'deviceId': id, 'name': id, 'online': true, 'dps': dps};

/// DP169 `first_calib`（2026-10-31 产品）：首用 / 恢复出厂后的教程与自动水位校准结束才报
/// true，默认 false。没上报过（旧固件）同样按 false，App 不让进设备页。
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  late MethodChannelTuyaRepository repository;

  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannel),
      (call) async => call.method == 'getDevices'
          ? <Object?>[
              _deviceMap('unreported', <Object?, Object?>{}),
              _deviceMap('pending', <Object?, Object?>{'169': false}),
              _deviceMap('done', <Object?, Object?>{'169': true}),
              _deviceMap('done-string', <Object?, Object?>{'169': 'true'}),
            ]
          : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannel),
      (call) async => null,
    );
    repository = MethodChannelTuyaRepository(
      channel: const MethodChannel(_methodChannel),
      events: const EventChannel(_eventChannel),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannel),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannel),
      null,
    );
  });

  test('169 没报过和报 false 都是未完成，报 true 才算完成', () async {
    final devices = await repository.getDevices();
    final byId = {for (final device in devices) device.id: device};

    expect(byId['unreported']!.firstCalibrated, isFalse);
    expect(byId['pending']!.firstCalibrated, isFalse);
    expect(byId['done']!.firstCalibrated, isTrue);
    expect(byId['done-string']!.firstCalibrated, isTrue);
  });
}
