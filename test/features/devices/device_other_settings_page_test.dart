import '../../support/plant_catalog.dart';
import '../../support/mock_tuya_repository.dart';
import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_other_settings_page.dart';
import 'package:flowerpot/src/features/devices/presentation/device_settings_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_config.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
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
    // 「系统文件更新」「修复系统文件」及其说明条已下线（都只是弹一句「暂未开放」）。
    expect(find.text('系统文件更新'), findsNothing);
    expect(find.textContaining('YSplanter的表情'), findsNothing);
    expect(find.text('修复系统文件'), findsNothing);
    expect(find.text('固件版本更新'), findsOneWidget);
    expect(find.text('V1.0.0'), findsOneWidget);
    expect(find.text('重新配网'), findsOneWidget);
    expect(find.text('恢复出厂设置'), findsOneWidget);
    expect(find.text('移除设备'), findsOneWidget);
    expect(findAssetImage(AppAssets.temperatureUnitIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('每一行调高到 56，375x812 一屏放下七行', (tester) async {
    // 2026-09-15 产品：列高适当调高一点，剩余高度足够。
    await _pumpOtherSettings(tester, const Size(375, 812));

    for (final key in const <String>[
      'water-level-calibration-setting',
      'firmware-update-setting',
      'repair-network-setting',
      'factory-reset-setting',
      'remove-device-setting',
    ]) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(56),
        reason: key,
      );
    }
    // 最后一行不用滚动就在屏幕里。
    expect(
      tester.getRect(find.byKey(const Key('remove-device-setting'))).bottom,
      lessThanOrEqualTo(812),
    );
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

  testWidgets('恢复出厂设置：确认后先下发 141，再用 resetFactory 解绑', (tester) async {
    // 2026-09-21 产品：「恢复出厂设置功能需要先下发恢复出厂 dp 再执行解除设备逻辑」。
    final repository = _OtherSettingsRepository();
    final state = await _pumpOtherSettings(
      tester,
      const Size(375, 812),
      repository: repository,
    );

    final reset = find.byKey(const Key('factory-reset-setting'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(repository.calls, <String>[
      'publishDps {${TuyaConfig.dp['factory_reset']}: true}',
      'resetFactory',
    ]);
    expect(state.deviceById('device-01'), isNull);
    expect(tester.takeException(), isNull);
    // 成功提示的计时器走完，别留下待处理的 Timer。
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets('恢复出厂设置：设备离线时不弹确认框、不下发也不解绑', (tester) async {
    final repository = _OtherSettingsRepository()..online = false;
    final state = await _pumpOtherSettings(
      tester,
      const Size(375, 812),
      repository: repository,
    );

    final reset = find.byKey(const Key('factory-reset-setting'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-dialog-confirm')), findsNothing);
    expect(find.text('设备已离线'), findsOneWidget);
    expect(repository.calls, isEmpty);
    expect(state.deviceById('device-01'), isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
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

  testWidgets('弹窗的两个版本来自同一条 OTA 记录', (tester) async {
    // 设备列表里的固件版本是 1.0.0，而这次待升级的组件当前跑的是 2.0.0。两行
    // 版本号必须成对来自 OTA 记录，否则「当前版本」和「新版本」不是同一个东西。
    await _pumpOtherSettings(
      tester,
      const Size(375, 812),
      repository: _OtherSettingsRepository(
        firmware: '2.1.0',
        currentFirmware: '2.0.0',
      ),
    );

    await tester.tap(find.text('固件版本更新'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firmware-update-dialog')), findsOneWidget);
    expect(find.text('V2.0.0'), findsOneWidget);
    expect(find.text('V2.1.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('installing firmware waits for the device to report success', (
    tester,
  ) async {
    final repository = _OtherSettingsRepository();
    final state = await _pumpOtherSettings(
      tester,
      const Size(375, 812),
      repository: repository,
    );

    await tester.tap(find.text('固件版本更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('install-firmware-update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 点「立即更新」只是通知涂鸦给设备下发升级：设备还在下载烧录，版本号不能
    // 提前改。还没有进度时写「固件准备中」，不写「0%」（2026-09-15 产品：像卡住了）。
    expect(state.deviceById('device-01')?.firmwareVersion, '1.0.0');
    expect(find.byKey(const Key('ota-progress-dialog')), findsOneWidget);
    // 同样按 key 取标题：「固件准备中」这一句弹层和后面的功能行会同时显示，
    // find.text 会数到两个。
    expect(
      tester.widget<Text>(find.byKey(const Key('ota-progress-title'))).data,
      '固件准备中',
    );
    expect(find.text('0%'), findsNothing);

    repository.pushOtaProgress(
      const OtaProgress(
        deviceId: 'device-01',
        status: OtaStatus.running,
        percent: 42,
      ),
    );
    await tester.pump();
    expect(find.text('固件升级中'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);

    repository.pushOtaProgress(
      const OtaProgress(
        deviceId: 'device-01',
        status: OtaStatus.running,
        percent: 98,
      ),
    );
    await tester.pump();
    // 2026-09-18 用户：涂鸦常常从 9x 直接跳进安装中，98% 一闪而过甚至根本没露面，
    // 看着就是「92% 之后忽然换了一句话」。所以收到 98 的**第一拍先把 98% 亮出来**，
    // 仍然是「固件升级中」的样子：有数字、进度条是确定值。
    expect(
      tester.widget<Text>(find.byKey(const Key('ota-progress-title'))).data,
      '固件升级中',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('ota-progress-percent'))).data,
      '98%',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('ota-progress-bar')),
          )
          .value,
      0.98,
    );

    // 亮够一拍（0.9s）之后才换成安装中。以下这组断言是 2026-09-17 产品定的口径，
    // 一个字没改，只是挪到了这一拍之后：98% 之后涂鸦要停一大段等设备写固件、重启，
    // 停在「98%」像卡死了，所以换成「固件准备中」那套不定进度动效 + 文案「固件安装中」、不写数字。
    // 按 key 取弹层里那几个控件，不用 find.text：这一句「固件安装中」和「其他设置」
    // 功能行上那句是同一个字符串（`otaRunningLabel` 两处共用），findsOneWidget 会打架。
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      tester.widget<Text>(find.byKey(const Key('ota-progress-title'))).data,
      '固件安装中',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('ota-progress-percent'))).data,
      '',
    );
    expect(find.text('98%'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('ota-progress-bar')),
          )
          .value,
      isNull,
    );

    repository.pushOtaProgress(
      const OtaProgress(deviceId: 'device-01', status: OtaStatus.success),
    );
    await tester.pumpAndSettle();

    expect(state.deviceById('device-01')?.firmwareVersion, '1.1.2');
    expect(find.text('V1.1.2'), findsOneWidget);
    // 装上了，红点灭掉。
    expect(find.byType(AppNoticeDot), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('固件版本更新：离线时提示「花盆已离线」，不弹框也不升级', (tester) async {
    // 2026-09-24 用户：离线也拦，花盆同步割草机的提示，不跳页。
    final repository = _OtherSettingsRepository()..online = false;
    final state = await _pumpOtherSettings(
      tester,
      const Size(375, 812),
      repository: repository,
    );

    await tester.tap(find.text('固件版本更新'));
    await tester.pumpAndSettle();

    expect(find.text('花盆已离线，无法检查固件'), findsOneWidget);
    expect(find.byKey(const Key('firmware-update-dialog')), findsNothing);
    expect(state.otaProgressFor('device-01'), isNull);
    expect(find.byType(DeviceOtherSettingsPage), findsOneWidget, reason: '不跳页');
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets('升级中再点「固件版本更新」：重新打开进度弹层', (tester) async {
    // 2026-09-24 用户：花盆同步割草机的，升级中点入口打开进度弹层（原来只弹一句提示）。
    final repository = _OtherSettingsRepository();
    final state = await _pumpOtherSettings(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await state.upgradeFirmware('device-01', '1.1.2');
    await tester.pump();
    expect(find.byKey(const Key('ota-progress-dialog')), findsNothing);

    await tester.tap(find.text('固件版本更新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('ota-progress-dialog')), findsOneWidget);
    expect(find.byKey(const Key('firmware-update-dialog')), findsNothing);

    // 收尾：报成功，停掉进度条的循环动画。
    repository.pushOtaProgress(
      const OtaProgress(deviceId: 'device-01', status: OtaStatus.success),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('OTA 兜底：DP148 报了目标版本，进度弹层换成「升级完成」', (tester) async {
    // 2026-09-24 用户：和涂鸦成功回调并存，任何一方满足就跳成功页。这里只报版本号、不报回调。
    final repository = _OtherSettingsRepository();
    final state = await _pumpOtherSettings(
      tester,
      const Size(375, 812),
      repository: repository,
    );
    await tester.tap(find.text('固件版本更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('install-firmware-update')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('ota-progress-dialog')), findsOneWidget);

    repository.pushDeviceUpdate(
      DeviceUpdate.changed(
        _device.copyWith(firmwareVersion: '1.1.2'),
        changedDps: <int>{TuyaConfig.dp['firmware_version']!},
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('ota-progress-title'))).data,
      '升级完成',
    );
    expect(find.byKey(const Key('ota-progress-close')), findsOneWidget);
    expect(state.deviceById('device-01')?.firmwareVersion, '1.1.2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a firmware waiting to be installed shows a red dot', (
    tester,
  ) async {
    // 进页面就静默问一次涂鸦，用户不点也知道有新版本。
    final state = await _pumpOtherSettings(tester, const Size(375, 812));
    await tester.pump();

    expect(state.availableFirmwareFor('device-01')?.version, '1.1.2');
    expect(find.byType(AppNoticeDot), findsOneWidget);
    // 红点不代替版本号：行上仍然显示设备当前跑的那个。
    expect(find.text('V1.0.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device already on the latest firmware shows no dot', (
    tester,
  ) async {
    final state = await _pumpOtherSettings(
      tester,
      const Size(375, 812),
      repository: _OtherSettingsRepository(firmware: '1.0.0'),
    );
    await tester.pump();

    expect(state.hasFirmwareUpdate('device-01'), isFalse);
    expect(find.byType(AppNoticeDot), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从升级提醒过来：进页面弹固件升级框，确认后才升级', (tester) async {
    // 2026-09-23 产品：「立刻更新」→ 关提醒弹窗、跳到其他设置、再弹固件升级框（此前是直接升级）。
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = await _stateWithDevice();
    addTearDown(state.dispose);
    await state.refreshFirmwareUpdate('device-01');

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceOtherSettingsPage(
            deviceId: 'device-01',
            startFirmwareUpgrade: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('firmware-update-dialog')), findsOneWidget);
    expect(state.otaProgressFor('device-01'), isNull, reason: '没确认之前不升级');
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
  Size size, {
  _OtherSettingsRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = await _stateWithDevice(repository);
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

Future<FlowerpotState> _stateWithDevice([
  _OtherSettingsRepository? repository,
]) async {
  final state = FlowerpotState(
    repository: repository ?? _OtherSettingsRepository(),
  );
  await state.initialize();
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
  _OtherSettingsRepository({this.firmware = '1.1.2', this.currentFirmware})
    : super(latency: Duration.zero);

  /// 云端待装的版本；给的和设备当前版本一样就表示「已是最新」。
  final String? firmware;

  /// 涂鸦在同一条 OTA 记录里报的当前版本，null 表示 SDK 没给。
  final String? currentFirmware;

  /// 设备在不在线（恢复出厂的门禁用）。
  bool online = true;

  /// 下发与解绑按发生顺序记下来：恢复出厂要求 141 在前、解绑在后。
  final List<String> calls = <String>[];

  @override
  Future<List<SmartPlanterDevice>> getDevices() async => <SmartPlanterDevice>[
    _device.copyWith(online: online),
  ];

  @override
  Future<void> publishDps(String deviceId, Map<int, Object> dps) {
    calls.add('publishDps $dps');
    return super.publishDps(deviceId, dps);
  }

  @override
  Future<void> removeDevice(String deviceId, {required bool resetFactory}) {
    calls.add(resetFactory ? 'resetFactory' : 'removeDevice');
    return super.removeDevice(deviceId, resetFactory: resetFactory);
  }

  @override
  Future<FirmwareUpdate?> checkFirmware(String deviceId) async {
    final version = firmware;
    return version == null
        ? null
        : FirmwareUpdate(version: version, currentVersion: currentFirmware);
  }

  /// 真实桥接只把升级发起出去就返回，进度和成败走事件通道。
  @override
  Future<void> startFirmwareUpgrade(String deviceId) async {}
}
