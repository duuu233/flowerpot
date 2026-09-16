import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/models/battery_status_page_model.dart';
import 'package:flowerpot/src/features/devices/models/humidity_status_page_model.dart';
import 'package:flowerpot/src/features/devices/models/light_status_page_model.dart';
import 'package:flowerpot/src/features/devices/models/temperature_status_page_model.dart';
import 'package:flowerpot/src/features/devices/models/water_status_page_model.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/battery_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/humidity_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/light_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/status_metric_icon.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/temperature_status_summary_card.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_status_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-09-15 产品：光照、湿度、温度三个状态页卡片底部的图标太小、位置不对，
/// 需水是正常的——三页的图标大小与位置都要和需水卡一致；电池状态随后提了同一个问题。
void main() {
  const water = WaterStatusPageModel(
    deviceId: 'device-01',
    status: '喝水中',
    description: '正在慢慢吸收水分。',
    waterLevel: 80,
    soilMoisture: 97,
    advice: '当前湿度适宜。',
  );
  const light = LightStatusPageModel(
    deviceId: 'device-01',
    status: '阳光明媚',
    description: '今天的阳光正好。',
    illuminance: 305,
    ppfd: 5.642,
    dliValues: <double>[.74, .67, .58, .61, .90, .63, .45],
    advice: '当前光照基本够用。',
  );
  const temperature = TemperatureStatusPageModel(
    deviceId: 'device-01',
    status: '温度适宜',
    description: '这个温度很舒服。',
    temperature: 26.9,
    advice: '适宜温度范围为18°C~28°C。',
  );
  const battery = BatteryStatusPageModel(
    deviceId: 'device-01',
    status: '充电中',
    description: '已连接电源，建议长期连接电源使用。',
    battery: 94,
    charging: true,
  );
  const humidity = HumidityStatusPageModel(
    deviceId: 'device-01',
    status: '很温润',
    description: '空气湿润又舒服。',
    humidity: 52,
    advice: '当前湿度适宜。',
  );

  /// 图标相对卡片左上角的位置。
  Future<List<Rect>> iconRects(
    WidgetTester tester,
    Widget card,
    Finder icons,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: card,
          ),
        ),
      ),
    );
    await tester.pump();
    final origin = tester.getRect(find.byType(AppSurfaceCard).first).topLeft;
    return <Rect>[
      for (var i = 0; i < icons.evaluate().length; i++)
        tester.getRect(icons.at(i)).shift(-origin),
    ];
  }

  Finder waterIcon(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(AppIconBadge),
  );

  testWidgets('light, temperature, humidity and battery icons match water', (
    tester,
  ) async {
    final level = (await iconRects(
      tester,
      const WaterStatusSummaryCard(model: water),
      waterIcon('water-metric-level'),
    )).single;
    final soil = (await iconRects(
      tester,
      const WaterStatusSummaryCard(model: water),
      waterIcon('water-metric-soil'),
    )).single;
    expect(level.size, const Size(40, 40));
    expect(level.left, closeTo(26, 0.01));

    final lightIcons = await iconRects(
      tester,
      const LightStatusSummaryCard(model: light),
      find.byType(StatusMetricIcon),
    );
    expect(lightIcons, hasLength(2));
    expect(lightIcons[0].size, level.size);
    expect(lightIcons[0].left, closeTo(level.left, 0.01));
    expect(lightIcons[1].size, soil.size);
    expect(lightIcons[1].left, closeTo(soil.left, 0.01));
    expect(tester.takeException(), isNull);

    for (final card in const <Widget>[
      TemperatureStatusSummaryCard(model: temperature),
      HumidityStatusSummaryCard(model: humidity),
      BatteryStatusSummaryCard(model: battery),
    ]) {
      final icon = (await iconRects(
        tester,
        card,
        find.byType(StatusMetricIcon),
      )).single;
      final name = '${card.runtimeType}';
      expect(icon.size, level.size, reason: name);
      expect(icon.left, closeTo(level.left, 0.01), reason: name);
      expect(tester.takeException(), isNull, reason: name);
    }
  });

  testWidgets('padded status artwork is scaled so the circle is still 40', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: StatusMetricIcon(
            assetPath: AppAssets.statusHumidityIcon,
            transparentInset: StatusMetricIcon.statusIconInset,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(StatusMetricIcon)), const Size(40, 40));
    final drawn = tester.getSize(find.byType(Image)).width;
    // 80 张图里圆底占 66：画出来的圆 = drawn × 66 / 80。
    expect(drawn * 66 / 80, closeTo(40, 0.01));
  });
}
