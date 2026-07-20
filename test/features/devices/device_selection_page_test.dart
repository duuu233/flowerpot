import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/design_system/design_system.dart';
import 'package:flowerpot/src/features/devices/presentation/device_selection_page.dart';
import 'package:flowerpot/src/routes/app_routes.dart';
import 'package:flowerpot/src/state.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('device selection page exposes the Figma content', (
    tester,
  ) async {
    await _pumpDeviceSelectionPage(tester, const Size(375, 812));

    expect(find.text('选择设备'), findsOneWidget);
    expect(find.text('请选择需要连接的设备'), findsOneWidget);
    expect(find.text('YSplanter-01'), findsOneWidget);
    expect(find.text('YSplanter-02'), findsOneWidget);
    expect(find.text('YSplanter-03'), findsOneWidget);
    expect(find.text('连接'), findsNWidgets(3));
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device selection content remains usable at 320x568', (
    tester,
  ) async {
    await _pumpDeviceSelectionPage(tester, const Size(320, 568));

    final lastDevice = find.text('YSplanter-03');
    await tester.ensureVisible(lastDevice);
    await tester.pump();

    expect(lastDevice, findsOneWidget);
    expect(find.byKey(const Key('connect-device-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connect pairs the selected device and opens success page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(
      repository: MockTuyaRepository(latency: Duration.zero),
    );
    addTearDown(state.dispose);
    Object? successArguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSelectionPage(
            request: PairingRequest(ssid: 'Home_2.4G', password: '12345678'),
          ),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.pairingSuccess) {
              successArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('pairing-success-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('connect-device-0')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('pairing-success-target'), findsOneWidget);
    expect(successArguments, 'planter-demo-01');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pairing errors open the failure page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = FlowerpotState(repository: _FailingRepository());
    addTearDown(state.dispose);
    Object? failureArguments;

    await tester.pumpWidget(
      FlowerpotScope(
        state: state,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DeviceSelectionPage(
            request: PairingRequest(ssid: 'Home_2.4G', password: '12345678'),
          ),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.pairingFailure) {
              failureArguments = settings.arguments;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Center(child: Text('pairing-failure-target')),
                ),
              );
            }
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('connect-device-0')));
    await tester.pumpAndSettle();

    expect(find.text('pairing-failure-target'), findsOneWidget);
    expect(failureArguments, isA<PairingRequest>());
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDeviceSelectionPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = FlowerpotState(
    repository: MockTuyaRepository(latency: Duration.zero),
  );
  addTearDown(state.dispose);
  await tester.pumpWidget(
    FlowerpotScope(
      state: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const DeviceSelectionPage(),
      ),
    ),
  );
  await tester.pump();
}

class _FailingRepository extends MockTuyaRepository {
  _FailingRepository() : super(latency: Duration.zero);

  @override
  Future<SmartPlanterDevice> pair(PairingRequest request) async {
    throw const TuyaException('pair_failed', '配网失败');
  }
}
