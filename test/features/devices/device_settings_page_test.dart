import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/device_settings_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/device_settings_function_list.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/device_settings_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('device settings widgets expose the Figma content', (
    tester,
  ) async {
    final selected = <DeviceSettingsMenuKind>[];
    await _pumpSettings(tester, const Size(375, 812), onItemTap: selected.add);

    expect(find.text('YSplanter-01'), findsOneWidget);
    expect(find.text('已陪伴52天'), findsOneWidget);
    expect(find.text('功能设置'), findsOneWidget);
    expect(find.text('选择植物'), findsOneWidget);
    expect(find.text('冷水花'), findsOneWidget);
    expect(find.text('其他设置'), findsOneWidget);
    // 2026-09-14 帮助中心挪到首页快捷列表，设置页不再有这一行。
    expect(find.text('帮助中心'), findsNothing);

    await tester.tap(find.text('显示'));
    expect(selected, <DeviceSettingsMenuKind>[DeviceSettingsMenuKind.display]);
  });

  testWidgets('a waiting firmware puts a red dot on 其他设置', (tester) async {
    // 固件在「其他设置」里面，红点是用户在外面唯一能看见的提示。
    await _pumpSettings(tester, const Size(375, 812), firmwareUpdate: true);

    expect(find.byType(AppNoticeDot), findsOneWidget);
    expect(find.text('其他设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no red dot when there is nothing to install', (tester) async {
    await _pumpSettings(tester, const Size(375, 812));

    expect(find.byType(AppNoticeDot), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device settings content scrolls at 320x568', (tester) async {
    await _pumpSettings(tester, const Size(320, 568));

    final target = find.text('其他设置');
    await tester.ensureVisible(target);
    await tester.pump();

    expect(target, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  Size size, {
  ValueChanged<DeviceSettingsMenuKind>? onItemTap,
  bool firmwareUpdate = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final model = DeviceSettingsPageModel(
    deviceId: 'device-01',
    deviceName: 'YSplanter-01',
    plantName: '冷水花',
    companionDays: 52,
    menuItems: <DeviceSettingsMenuItem>[
      const DeviceSettingsMenuItem(
        kind: DeviceSettingsMenuKind.plant,
        label: '选择植物',
        value: '冷水花',
      ),
      const DeviceSettingsMenuItem(
        kind: DeviceSettingsMenuKind.display,
        label: '显示',
        value: '自动',
      ),
      const DeviceSettingsMenuItem(
        kind: DeviceSettingsMenuKind.hearing,
        label: '听觉感知',
        value: '已开启',
      ),
      const DeviceSettingsMenuItem(
        kind: DeviceSettingsMenuKind.touch,
        label: '触觉感知',
        value: '已开启',
      ),
      const DeviceSettingsMenuItem(
        kind: DeviceSettingsMenuKind.vibration,
        label: '震动设置',
        value: '已禁用',
      ),
      const DeviceSettingsMenuItem(
        kind: DeviceSettingsMenuKind.behavior,
        label: '行为',
      ),
      DeviceSettingsMenuItem(
        kind: DeviceSettingsMenuKind.other,
        label: '其他设置',
        badge: firmwareUpdate,
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              DeviceSettingsSummaryCard(model: model, onMore: () {}),
              const SizedBox(height: 20),
              DeviceSettingsFunctionList(
                items: model.menuItems,
                onItemTap: onItemTap ?? (_) {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
