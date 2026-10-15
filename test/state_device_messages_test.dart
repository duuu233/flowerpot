import 'package:flowerpot/src/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/mock_tuya_repository.dart';

class _MessagesRepository extends MockTuyaRepository {
  _MessagesRepository({this.failOffset}) : super(latency: Duration.zero);
  final int? failOffset;
  final requests = <(String, String, int, int)>[];
  @override
  Future<Map<String, Object?>> deviceMessages({
    required String deviceId,
    String msgType = 'MSG_REPORT',
    int offset = 0,
    int limit = 50,
  }) async {
    requests.add((deviceId, msgType, offset, limit));
    if (offset == failOffset) return {'ok': false, 'message': '示例查询失败'};
    final end = (offset + limit).clamp(0, 123);
    return {
      'ok': true,
      'totalCount': 123,
      'items': [
        for (var i = offset; i < end; i++)
          {
            'msgTitle': '消息$i',
            'time': 1800000000 - i,
            'msgContent': '真实接口字段示例',
            'extendParams': '{"level":"通知"}',
          },
      ],
    };
  }
}

void main() {
  test('云端消息按指定设备和MSG_REPORT翻页，完整返回且不重复', () async {
    final repository = _MessagesRepository();
    final state = FlowerpotState(repository: repository);
    addTearDown(state.dispose);
    final result = await state.loadAllDeviceMessages(
      deviceId: 'selected-device',
    );
    expect(repository.requests, [
      ('selected-device', 'MSG_REPORT', 0, 50),
      ('selected-device', 'MSG_REPORT', 50, 50),
      ('selected-device', 'MSG_REPORT', 100, 50),
    ]);
    expect(result['ok'], isTrue);
    expect(result['partial'], isFalse);
    expect((result['items'] as List).length, 123);
    expect(
      (result['items'] as List).map((item) => item['msgTitle']).toSet().length,
      123,
    );
  });
  test('云端消息后续页失败保留已取得条目并标记partial，不伪造完整成功', () async {
    final state = FlowerpotState(
      repository: _MessagesRepository(failOffset: 50),
    );
    addTearDown(state.dispose);
    final result = await state.loadAllDeviceMessages(
      deviceId: 'selected-device',
    );
    expect(result['ok'], isTrue);
    expect(result['partial'], isTrue);
    expect((result['items'] as List).length, 50);
  });
}
