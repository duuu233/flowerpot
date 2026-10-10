import 'package:flowerpot/src/features/mower/mower_command_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DP115 按十进制解析，忽略未知字段，val可省略', () {
    final result = MowerCommandResult.parse(
      '{"code":26,"seq":255,"dp":3,"val":1,"future":true}',
    )!;
    expect(result.code, 26);
    expect(result.seq, 255);
    expect(result.dp, 3);
    expect(result.value, 1);
    expect(result.rejectionMessage, '请先排除机器故障');
    expect(
      MowerCommandResult.parse({'code': 16, 'seq': 0, 'dp': 2})!.value,
      isNull,
    );
  });
  test('DP115 畸形、缺字段、错误类型和越界帧不猜结果', () {
    for (final raw in <Object?>[
      null,
      'invalid',
      '[]',
      'null',
      {'code': 26, 'dp': 3},
      {'code': '26', 'seq': 1, 'dp': 3},
      {'code': 26.5, 'seq': 1, 'dp': 3},
      {'code': -1, 'seq': 1, 'dp': 3},
      {'code': 256, 'seq': 1, 'dp': 3},
      {'code': 26, 'seq': 256, 'dp': 3},
      {'code': 26, 'seq': 1, 'dp': 0},
      {'code': 26, 'seq': 1, 'dp': 3, 'val': true},
    ]) {
      expect(MowerCommandResult.parse(raw), isNull, reason: '$raw');
    }
  });
  test('code小于16无异常提示，所有定义的状态码按协议建议显示', () {
    for (var code = 0; code < 16; code++) {
      expect(
        MowerCommandResult(code: code, seq: 0, dp: 2).rejectionMessage,
        isNull,
      );
    }
    const expected = <int, String>{
      16: '机器已关机',
      17: '开机自检中，请稍候',
      18: '设备升级中，请稍后再试',
      19: '机器处于急停',
      21: '请盖上盖子',
      22: '面板已锁定，请先解锁',
      23: '请松开急停按钮',
      24: '机器正在找线，请稍候或放回线内',
      25: '检查边界线供电/机器位置',
      26: '请先排除机器故障',
    };
    for (final entry in expected.entries) {
      expect(
        MowerCommandResult(code: entry.key, seq: 0, dp: 3).rejectionMessage,
        entry.value,
      );
    }
    for (final code in <int>[20, 27, 31, 32, 65, 255]) {
      expect(
        MowerCommandResult(code: code, seq: 0, dp: 3).rejectionMessage,
        '操作未生效（码 $code）',
      );
    }
  });
}
