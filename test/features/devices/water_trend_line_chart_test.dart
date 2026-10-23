import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/widgets/water_trend_line_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 状态页折线图：零下的温度、没采到（以 0 补齐）的点。
void main() {
  Future<void> pumpChart(
    WidgetTester tester, {
    required List<double> values,
    List<bool> gaps = const <bool>[],
    List<String> labels = const <String>['00:00', '04:00'],
    List<double>? labelPositions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 335,
              height: 188,
              child: WaterTrendLineChart(
                values: values,
                gaps: gaps,
                labels: labels,
                labelPositions: labelPositions,
                unit: '°C',
                maxValue: 50,
                fractionDigits: 1,
                semanticsName: '空气温度趋势图',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('零下的温度照常画，选中点显示负数', (tester) async {
    await pumpChart(tester, values: <double>[-12.5, -3, 0, 4.5, 8]);

    // 默认选中 (5 − 1) × 0.57 ≈ 第 2 个点。
    expect(find.bySemanticsLabel(RegExp('当前选中0.0°C')), findsOneWidget);
    // 绘图区从左边 34 像素起：点在最左边就是第一个点。
    final origin = tester.getTopLeft(find.byType(WaterTrendLineChart));
    await tester.tapAt(origin + const Offset(36, 100));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('当前选中-12.5°C')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认选中点落在没采到的点上时挪到最近有数的点', (tester) async {
    await pumpChart(
      tester,
      values: <double>[20, 0, 0, 0, 22],
      gaps: <bool>[false, true, true, true, false],
    );

    expect(find.bySemanticsLabel(RegExp('当前选中22.0°C')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点到没采到的点上显示「未采集」', (tester) async {
    await pumpChart(
      tester,
      values: <double>[20, 0, 0, 0, 22],
      gaps: <bool>[false, true, true, true, false],
    );
    final chart = find.byType(WaterTrendLineChart);
    await tester.tapAt(tester.getCenter(chart));
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp('当前选中未采集')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('整段都没采到、只有一个点、标签按点位放，都不报错', (tester) async {
    await pumpChart(
      tester,
      values: <double>[0, 0, 0],
      gaps: <bool>[true, true, true],
    );
    expect(tester.takeException(), isNull);

    await pumpChart(tester, values: <double>[-60]);
    expect(tester.takeException(), isNull);

    await pumpChart(
      tester,
      values: <double>[1, 2, 3, 4, 5, 6],
      labels: <String>['09:00', '09:15'],
      labelPositions: <double>[0, 1],
    );
    expect(tester.takeException(), isNull);
  });
}
