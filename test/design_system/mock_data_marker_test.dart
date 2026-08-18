import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the badges name the data source in debug builds', (
    tester,
  ) async {
    await _pump(
      tester,
      const Column(
        children: <Widget>[MockDataBadge(), LiveDataBadge()],
      ),
    );

    expect(find.text('测试数据'), findsOneWidget);
    expect(find.text('真实 SDK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom label replaces the default one', (tester) async {
    await _pump(tester, const MockDataBadge(label: '模拟设备名'));

    expect(find.text('模拟设备名'), findsOneWidget);
    expect(find.text('测试数据'), findsNothing);
  });

  testWidgets('an invisible marker renders nothing at all', (tester) async {
    await _pump(
      tester,
      const Column(
        children: <Widget>[
          MockDataBadge(visible: false),
          LiveDataBadge(visible: false),
          MockDataBanner(message: '不应出现', visible: false),
        ],
      ),
    );

    expect(find.text('测试数据'), findsNothing);
    expect(find.text('真实 SDK'), findsNothing);
    expect(find.text('不应出现'), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the banner shows both its title and its explanation', (
    tester,
  ) async {
    await _pump(
      tester,
      const MockDataBanner(title: '模拟搜索', message: '雷达只是动画。'),
    );

    expect(find.text('模拟搜索'), findsOneWidget);
    expect(find.text('雷达只是动画。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long banner message wraps instead of overflowing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      const MockDataBanner(
        title: '模拟设备列表',
        message: '下面三台是写死的示例设备，没有经过蓝牙搜索。选哪一台都不影响后面的真实配网，'
            '只会带一个名字过去。',
      ),
    );

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(alignment: Alignment.topCenter, child: child),
      ),
    ),
  );
  await tester.pump();
}
