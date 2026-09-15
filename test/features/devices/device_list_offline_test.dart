import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/core/network/network_status.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_list_page.dart';
import 'package:flowerpot/src/features/home/presentation/home_page.dart';
import 'package:flowerpot/src/features/shell/presentation/shell_page.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mock_tuya_repository.dart';

/// 2026-09-15 产品：手机没网时不能进「添加设备」页，改为进设备列表的无网络缺省页
/// （「当前网络不可用，请检查网络后重试」+「重试」）。全局弹窗另外保留。
void main() {
  late bool online;

  setUp(() {
    online = false;
    NetworkStatus.probe = () async => online;
  });

  Future<(FlowerpotState, _FlakyDevices)> signIn(WidgetTester tester) async {
    final repository = _FlakyDevices();
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    await tester.runAsync(
      () => state.login(
        account: '13800138000',
        credential: 'demo',
        region: LoginRegion.domestic,
        verificationCode: false,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(theme: buildAppTheme(), home: const AppShell()),
      ),
    );
    await tester.pump();
    return (state, repository);
  }

  testWidgets('offline with no devices lands on the list placeholder', (
    tester,
  ) async {
    final (state, _) = await signIn(tester);

    expect(state.devices, isEmpty);
    expect(state.deviceLoadOffline, isTrue);
    expect(find.byType(DeviceListPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(find.text('当前网络不可用，请检查网络后重试'), findsOneWidget);
    expect(
      find.byKey(const Key('device-list-offline-retry')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry once back online shows the devices', (tester) async {
    final (state, repository) = await signIn(tester);

    online = true;
    repository.failing = false;
    await tester.runAsync(state.reloadDevices);
    await tester.pump();

    expect(state.deviceLoadOffline, isFalse);
    expect(find.text('当前网络不可用，请检查网络后重试'), findsNothing);
    expect(find.byType(DeviceListPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failure while online still falls back to the old page', (
    tester,
  ) async {
    online = true;
    final (state, _) = await signIn(tester);

    expect(state.deviceLoadError, isNotNull);
    expect(state.deviceLoadOffline, isFalse);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('当前网络不可用，请检查网络后重试'), findsNothing);
  });
}

class _FlakyDevices extends MockTuyaRepository {
  _FlakyDevices() : super(latency: Duration.zero);

  bool failing = true;

  @override
  Future<List<SmartPlanterDevice>> getDevices() {
    if (failing) {
      return Future<List<SmartPlanterDevice>>.error(
        const TuyaException('network_error', '网络连接失败'),
      );
    }
    return super.getDevices();
  }
}
