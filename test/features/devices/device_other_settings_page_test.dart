import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_other_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('other settings page exposes the Figma content', (tester) async {
    await _pumpOtherSettings(tester, const Size(375, 812));

    expect(find.text('其他设置'), findsOneWidget);
    expect(find.text('温度单位'), findsOneWidget);
    expect(find.text('摄氏度（℃）'), findsOneWidget);
    expect(find.text('时钟模式'), findsOneWidget);
    expect(find.text('24小时'), findsOneWidget);
    expect(find.text('水位传感器校准'), findsOneWidget);
    expect(find.text('系统文件更新'), findsOneWidget);
    expect(find.textContaining('YSplanter的表情'), findsOneWidget);
    expect(find.text('固件版本更新'), findsOneWidget);
    expect(find.text('V1.0.0'), findsOneWidget);
    expect(find.text('修复系统文件'), findsOneWidget);
    expect(find.text('重新配网'), findsOneWidget);
    expect(find.text('恢复出厂设置'), findsOneWidget);
    expect(find.text('移除设备'), findsOneWidget);
    expect(findAssetImage(AppAssets.temperatureUnitIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('other settings remain scrollable at 320x568', (tester) async {
    await _pumpOtherSettings(tester, const Size(320, 568));

    final removeDevice = find.byKey(const Key('remove-device-setting'));
    await tester.ensureVisible(removeDevice);
    await tester.pump();

    expect(removeDevice, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temperature unit can be changed', (tester) async {
    final state = await _pumpOtherSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('temperature-unit-setting')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('temperature-unit-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('temperature-unit-drag-handle')),
      findsOneWidget,
    );
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(find.text('摄氏度（℃）'), findsNWidgets(2));
    expect(find.text('华氏度（℉）'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fahrenheit-temperature-unit')));
    await tester.tap(find.byKey(const Key('confirm-temperature-unit')));
    await tester.pumpAndSettle();

    expect(
      state.deviceById('device-01')?.settings.temperatureUnit,
      'fahrenheit',
    );
    expect(find.text('华氏度（℉）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clock format can be changed from the Figma bottom sheet', (
    tester,
  ) async {
    final state = await _pumpOtherSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('clock-format-setting')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('clock-format-sheet')), findsOneWidget);
    expect(find.byKey(const Key('clock-format-drag-handle')), findsOneWidget);
    expect(find.text('时钟模式'), findsNWidgets(2));
    expect(find.text('12小时'), findsOneWidget);
    expect(find.text('24小时'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('12h-clock-format')));
    await tester.tap(find.byKey(const Key('confirm-clock-format')));
    await tester.pumpAndSettle();

    expect(state.deviceById('device-01')?.settings.clockFormat, '12h');
    expect(find.text('12小时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('water level calibration follows all four Figma steps', (
    tester,
  ) async {
    await _pumpOtherSettings(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('water-level-calibration-setting')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('water-level-calibration-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('water-level-calibration-stepper')),
      findsOneWidget,
    );
    expect(find.text('水位传感器校准'), findsNWidgets(2));
    expect(find.text('请先移出植物内胆，\n并倒空水仓中的剩余水。'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calibration-primary-button')));
    await tester.pumpAndSettle();

    expect(find.text('请向水仓中倒入30mL水，\n并点击“下一步”确认'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calibration-primary-button')));
    await tester.pumpAndSettle();

    expect(find.text('请再次向水仓中倒入30mL水，\n并再次点击“下一步”确认'), findsOneWidget);
    expect(
      find.byKey(const Key('water-level-calibration-step-3')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('再次向水仓倒入30毫升水示意图'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calibration-primary-button')));
    await tester.pumpAndSettle();

    expect(find.text('校准完成！'), findsOneWidget);
    expect(
      find.byKey(const Key('water-level-calibration-step-4')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('水位传感器校准完成'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);

    await tester.tap(find.byKey(const Key('calibration-primary-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('water-level-calibration-dialog')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('water level calibration fits a compact iPhone viewport', (
    tester,
  ) async {
    await _pumpOtherSettings(tester, const Size(320, 568));

    await tester.tap(find.byKey(const Key('water-level-calibration-setting')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('water-level-calibration-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('water-level-calibration-illustration')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('firmware check dialog matches the Figma content', (
    tester,
  ) async {
    final state = await _pumpOtherSettings(tester, const Size(375, 812));

    await tester.tap(find.text('固件版本更新'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firmware-update-dialog')), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('V1.0.0'), findsNWidgets(2));
    expect(find.text('V1.1.2'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);

    await tester.tap(find.byKey(const Key('postpone-firmware-update')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firmware-update-dialog')), findsNothing);
    expect(state.deviceById('device-01')?.firmwareVersion, '1.0.0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('installing available firmware refreshes the shown version', (
    tester,
  ) async {
    final state = await _pumpOtherSettings(tester, const Size(375, 812));

    await tester.tap(find.text('固件版本更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('install-firmware-update')));
    await tester.pumpAndSettle();

    expect(state.deviceById('device-01')?.firmwareVersion, '1.1.2');
    expect(find.text('V1.1.2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings menu opens the full other settings page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = await _stateWithDevice();
    addTearDown(state.dispose);
    Object? routeArguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSettingsPage(deviceId: 'device-01'),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.deviceOtherSettings) {
              routeArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('other-settings-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    final otherSettings = find.text('其他设置');
    await tester.ensureVisible(otherSettings);
    await tester.tap(otherSettings);
    await tester.pumpAndSettle();

    expect(find.text('other-settings-target'), findsOneWidget);
    expect(routeArguments, 'device-01');
    expect(tester.takeException(), isNull);
  });
}

Future<FlowerpotState> _pumpOtherSettings(
  WidgetTester tester,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = await _stateWithDevice();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const DeviceOtherSettingsPage(deviceId: 'device-01'),
      ),
    ),
  );
  await tester.pump();
  return state;
}

Future<FlowerpotState> _stateWithDevice() async {
  final state = FlowerpotState(repository: _OtherSettingsRepository());
  await state.refreshDevices();
  return state;
}

SmartPlanterDevice get _device => SmartPlanterDevice(
  id: 'device-01',
  productId: 'product-01',
  name: 'YSplanter-01',
  online: true,
  signal: 86,
  battery: 94,
  charging: false,
  boundAt: DateTime.now().subtract(const Duration(days: 51)),
  plant: PlantCatalog.items.first,
  sensors: const SensorSnapshot(
    waterLevel: 80,
    soilMoisture: 97,
    illuminance: 305,
    ppfd: 5.642,
    airTemperature: 26.9,
    relativeHumidity: 52,
  ),
  settings: const DeviceControlSettings(),
  firmwareVersion: '1.0.0',
  macAddress: 'D8:85:AC:A2:B9:B4',
);

class _OtherSettingsRepository extends MockTuyaRepository {
  _OtherSettingsRepository() : super(latency: Duration.zero);

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _device,
  ];

  @override
  Future<String?> checkFirmware(String deviceId) async => '1.1.2';

  @override
  Future<void> startFirmwareUpgrade(String deviceId) async {}
}
