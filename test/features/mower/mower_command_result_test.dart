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
  test('除内部失败3外小于16无提示，所有定义码按拒绝理由V1.0文案显示', () {
    for (var code = 0; code < 16; code++) {
      expect(
        MowerCommandResult(code: code, seq: 0, dp: 2).rejectionMessage,
        code == 3 ? '操作未生效，请重试' : isNull,
      );
    }
    const expected = <int, String>{
      16: '机器已关机',
      17: '开机自检中，请稍候',
      18: '固件升级中，暂不接受操作',
      19: '机器处于急停状态',
      21: '请合上盖子',
      22: '机器已锁定',
      23: '请松开急停按钮',
      24: '机器正在寻找边界线，请稍候',
      25: '边界信号丢失，请检查边界线',
      26: '请先排除机器故障',
      32: '机器已在充电桩上',
      33: '机器在界外，请移回界内',
      34: '电量低，正在充电',
      35: '雨天暂停中，雨停后自动继续',
      48: '请先选择工作模式',
      49: '机器在桩等待中',
      52: '上次任务已取消，请重新选择模式',
      53: '设备正忙，请稍后重试',
      54: '机器电量小于70%，已进入充电等待',
      64: '参数不在允许范围内',
      65: '数据长度不正确',
      66: '数据格式不正确',
      67: '数据类型不匹配',
      68: '该功能不支持设置',
      69: '请先开启自动同步',
      70: '设备不支持该功能',
    };
    for (final entry in expected.entries) {
      expect(
        MowerCommandResult(code: entry.key, seq: 0, dp: 3).rejectionMessage,
        entry.value,
      );
    }
    // 在桩等待三种拒绝各自独立，不再都落「在桩等待中」。
    final waits = <String?>{
      for (final code in <int>[35, 49, 54])
        MowerCommandResult(code: code, seq: 0, dp: 3).rejectionMessage,
    };
    expect(waits, hasLength(3));
    expect(
      const MowerCommandResult(code: 255, seq: 0, dp: 3).rejectionMessage,
      '操作未生效（码 255）',
    );
    for (final code in <int>[20, 27, 31]) {
      expect(
        MowerCommandResult(code: code, seq: 0, dp: 3).rejectionMessage,
        '操作未生效（码 $code）',
      );
    }
  });
}
