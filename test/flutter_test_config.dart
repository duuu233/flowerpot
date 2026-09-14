import 'dart:async';
import 'package:flowerpot/src/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 配网第三步那 1–2 秒随机停留（产品要的流程感）在用例里统一置零：配网 Mock 自己
    // 已经等 1 秒，再叠随机时长会让按固定时长 pump 的用例时好时坏。专门验它的用例
    // 自己换回来。
    FlowerpotState.cloudStageDelay = () => Duration.zero;
  });
  await testMain();
}
