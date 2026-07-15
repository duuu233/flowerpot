import 'package:flowerpot/src/app/flowerpot_app.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('experience mode reaches the device home', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      FlowerpotApp(repository: MockTuyaRepository(latency: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(find.text('照顾植物，\n也照顾生活。'), findsOneWidget);
    final demoButton = find.text('体验模式');
    await tester.ensureVisible(demoButton);
    await tester.pumpAndSettle();
    await tester.tap(demoButton);
    await tester.pumpAndSettle();

    expect(find.text('今天也要好好生长'), findsOneWidget);
    expect(find.text('客厅的绿意'), findsOneWidget);
  });
}
