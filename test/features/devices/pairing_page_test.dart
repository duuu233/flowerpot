import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/pairing_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/asset_finder.dart';

void main() {
  testWidgets('pairing page exposes the Figma content', (tester) async {
    await _pumpPairingPage(tester, const Size(375, 812));

    expect(find.text('连接Wi-Fi'), findsOneWidget);
    expect(find.text('请将设备连接到2.4GHz Wi-Fi网络'), findsOneWidget);
    expect(find.text('仅支持2.4GHz Wi-Fi网络'), findsOneWidget);
    expect(find.text('请确保设备连接的是稳定的2.4GHz网络'), findsOneWidget);
    expect(find.text('Wi-Fi名称'), findsOneWidget);
    expect(find.text('Home_2.4G'), findsOneWidget);
    expect(find.text('切换'), findsOneWidget);
    expect(find.text('Wi-Fi密码'), findsOneWidget);
    expect(find.text('连接过程中请保持设备靠近路由器'), findsOneWidget);
    expect(find.text('开始配网'), findsOneWidget);
    expect(
      findAssetImage(AppAssets.pairingWifiSetupIllustration),
      findsOneWidget,
    );
    final background = tester.widget<Image>(
      findAssetImage(AppAssets.accountBackground),
    );
    expect(background.fit, BoxFit.cover);
    expect(
      tester.getSize(find.byKey(const Key('wifi-connection-illustration'))),
      const Size(335, 270),
    );
    final noticeCard = tester.widget<DecoratedBox>(
      find.byKey(const Key('wifi-notice-card')),
    );
    expect(
      (noticeCard.decoration as BoxDecoration).color,
      AppColors.surfaceTranslucent,
    );

    final password = tester.widget<TextField>(
      find.byKey(const Key('pairing-password-field')),
    );
    expect(password.obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wifi selection sheet updates the network name', (tester) async {
    await _pumpPairingPage(tester, const Size(375, 812));

    await tester.tap(find.byKey(const Key('switch-wifi-button')));
    await tester.pumpAndSettle();
    expect(find.text('选择Wi-Fi'), findsOneWidget);
    expect(find.text('仅显示可用的2.4GHzWi-Fi网络'), findsOneWidget);
    expect(find.byKey(const Key('wifi-option-Home_2.4G')), findsOneWidget);
    expect(find.byKey(const Key('wifi-option-TP-LINK_2.4G')), findsOneWidget);
    expect(find.byKey(const Key('wifi-option-Xiaomi_2.4G')), findsOneWidget);
    expect(find.byKey(const Key('wifi-selected-check')), findsOneWidget);

    await tester.tap(find.byKey(const Key('wifi-option-TP-LINK_2.4G')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('wifi-selection-confirm')));
    await tester.pumpAndSettle();

    final ssid = tester.widget<TextField>(
      find.byKey(const Key('pairing-ssid-field')),
    );
    expect(ssid.controller?.text, 'TP-LINK_2.4G');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pairing content remains usable at 320x568', (tester) async {
    await _pumpPairingPage(tester, const Size(320, 568));

    final info = find.text('连接过程中请保持设备靠近路由器');
    await tester.ensureVisible(info);
    await tester.pump();

    expect(info, findsOneWidget);
    expect(find.text('开始配网'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPairingPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(theme: buildAppTheme(), home: const PairingPage()),
    ),
  );
  await tester.pump();
}
