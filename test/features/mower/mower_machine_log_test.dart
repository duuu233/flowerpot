import 'dart:convert';

import 'package:flowerpot/src/features/mower/mower_command_result.dart';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flowerpot/src/features/mower/mower_fault_alarm.dart';
import 'package:flowerpot/src/features/mower/mower_machine_log.dart';
import 'package:flowerpot/src/features/mower/presentation/widgets/mower_start_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime(2026, 10, 12, 12);
Map<String, int> _alarm({
  int device = 0,
  int error = 0,
  int function = 0,
  int circularize = 0,
}) => {
  'device': device,
  'error': error,
  'function': function,
  'circularize': circularize,
};
Map<int, Object?> _fault(Map<String, int> alarm) => {111: jsonEncode(alarm)};
void main() {
  test('DP18 正常、每一故障位、十进制和带进制前缀的位图', () {
    expect(MowerFault.firstMessage(0), isNull);
    for (var bit = 0; bit < 13; bit++) {
      expect(MowerFault.firstMessage(1 << bit), MowerFault.messages[bit]);
      expect(MowerFault.activeBits(1 << bit), [bit]);
    }
    expect(MowerFault.parseBitmap('8'), 8);
    expect(MowerFault.parseBitmap('0b1000'), 8);
    expect(MowerFault.parseBitmap('0x1000'), 4096);
    expect(MowerFault.firstMessage(1 << 13), isNull);
    for (final raw in [null, -1, 1.5, double.infinity, 'bad', 0x100000000]) {
      expect(MowerFault.parseBitmap(raw), isNull, reason: '$raw');
    }
  });
  test('DP111 必须完整、非负、整数、32位；不猜缺失层', () {
    expect(MowerFaultAlarm.parse(jsonEncode(_alarm(error: 6)))!.error, 6);
    for (final raw in [
      null,
      '{',
      '[]',
      {'error': 2},
      _alarm(device: -1),
      {..._alarm(), 'error': 1.5},
      _alarm(device: 0x100000000),
    ]) {
      expect(MowerFaultAlarm.parse(raw), isNull);
    }
  });
  test('code26 按层定位，硬件优先，安全次之，位置最后', () {
    final hardware = MowerFaultAlarm.parse(_alarm(device: 4, error: 4))!;
    expect(hardware.recoveryMessages.first, contains('存储异常'));
    expect(hardware.recoveryMessages.last, contains('边界线供电'));
    expect(
      MowerFaultAlarm.parse(_alarm(error: 2))!.recoveryMessage,
      contains('放回地面'),
    );
    expect(
      MowerFaultAlarm.parse(_alarm(error: 16384))!.recoveryMessage,
      contains('移回界内'),
    );
    expect(
      MowerFaultAlarm.parse(_alarm(device: 8))!.recoveryMessage,
      contains('左轮电机通信异常'),
    );
    expect(
      MowerFaultAlarm.parse(_alarm(function: 2))!.recoveryMessage,
      contains('暂未检测到'),
    );
  });
  test('code26 丢信号升级族补边界提示，通知与保留位不伪造故障', () {
    for (final value in [16, 131072, 262144]) {
      expect(
        MowerFaultAlarm.parse(_alarm(circularize: value))!.recoveryMessage,
        contains('边界线供电'),
      );
    }
    expect(
      MowerFaultAlarm.parse(
        _alarm(device: 64, error: 8192, circularize: 2),
      )!.recoveryMessage,
      contains('暂未检测到'),
    );
    expect(
      MowerFaultAlarm.parse(_alarm(device: 128))!.recoveryMessage,
      contains('未识别'),
    );
  });
  test('code26 处理建议附带现场处理及手动重试间隔，保留位提示反馈固件', () {
    final message = MowerFaultAlarm.parse(
      _alarm(device: 1, error: 2),
    )!.recoveryMessage;
    expect(message, contains('电池异常'));
    expect(message, contains('机器被抬起'));
    expect(message, contains('现场处理'));
    expect(message, contains('等待1～2秒'));
    expect(message, contains('手动重试原操作'));
    final reserved = MowerFaultAlarm.parse(
      _alarm(device: 64, error: 8192),
    )!.recoveryMessage;
    expect(reserved, contains('反馈固件问题'));
    expect(reserved, isNot(contains('电池异常')));
  });
  test('协议§8.6.1所有有效残留故障位都有具体处理建议', () {
    const hardware = <int, String>{
      1: '电池异常',
      2: '姿态传感器异常',
      4: '存储异常',
      8: '左轮电机通信异常',
      16: '右轮电机通信异常',
      32: '刀盘电机通信异常',
    };
    const errors = <int, String>{
      1: '扶正放平',
      2: '放回地面',
      4: '边界线供电',
      8: '左轮异常',
      16: '左轮异常',
      32: '左轮异常',
      64: '右轮异常',
      128: '右轮异常',
      256: '右轮异常',
      512: '刀盘异常',
      1024: '刀盘异常',
      2048: '刀盘异常',
      4096: '刀盘异常',
      16384: '移回界内',
      32768: '离开充电桩',
    };
    for (final item in hardware.entries) {
      expect(
        MowerFaultAlarm.parse(_alarm(device: item.key))!.recoveryMessage,
        contains(item.value),
        reason: 'device=${item.key}',
      );
    }
    for (final item in errors.entries) {
      expect(
        MowerFaultAlarm.parse(_alarm(error: item.key))!.recoveryMessage,
        contains(item.value),
        reason: 'error=${item.key}',
      );
    }
    final many = MowerFaultAlarm.parse(
      _alarm(device: 7, error: 6),
    )!.recoveryMessage;
    expect(many, contains('另有故障未排除'));
    expect(many, isNot(contains('机器被抬起')));
    expect(many, contains('手动重试原操作'));
  });
  test('DP115 32–70 定义码有具体文案，255 无内部码，小于16不弹', () {
    const expected = {
      32: '充电桩',
      33: '边界线内',
      34: '充电',
      35: '雨天',
      48: '工作模式',
      49: '等待',
      52: '取消',
      53: '正忙',
      64: '范围',
      65: '长度',
      66: '格式',
      67: '类型',
      68: '读取',
      69: '自动时间同步',
      70: '固件版本',
    };
    for (final item in expected.entries) {
      expect(
        MowerCommandResult(code: item.key, seq: 0, dp: 3).rejectionMessage,
        contains(item.value),
      );
    }
    expect(
      const MowerCommandResult(code: 255, seq: 0, dp: 3).rejectionMessage,
      '操作未生效',
    );
    for (var code = 0; code < 16; code++) {
      expect(
        MowerCommandResult(code: code, seq: 0, dp: 3).rejectionMessage,
        isNull,
      );
    }
  });
  test('负值与0时长不通过，18点之后不能跨天设置', () {
    expect(mowerStartHoursValid(_time, -1), isFalse);
    expect(mowerStartHoursValid(_time, 0), isFalse);
    expect(mowerStartHoursValid(_time, 6), isTrue);
    expect(mowerStartHoursValid(_time, 7), isFalse);
    expect(mowerStartHoursValid(DateTime(2026, 10, 12, 18), 1), isFalse);
    expect(mowerStartHoursValid(DateTime(2026, 10, 12, 19), -1), isFalse);
  });
  const cases = <(String, int, int)>[
    ('device', 1, 3),
    ('device', 2, 3),
    ('device', 4, 3),
    ('device', 8, 3),
    ('device', 16, 3),
    ('device', 32, 3),
    ('error', 1, 3),
    ('error', 2, 3),
    ('error', 4, 3),
    ('error', 8, 3),
    ('error', 16, 3),
    ('error', 32, 3),
    ('error', 64, 3),
    ('error', 128, 3),
    ('error', 256, 3),
    ('error', 1024, 3),
    ('error', 2048, 3),
    ('error', 4096, 3),
    ('error', 16384, 3),
    ('error', 32768, 3),
    ('function', 2, 3),
    ('circularize', 8, 2),
    ('circularize', 16, 2),
    ('circularize', 32, 2),
    ('circularize', 4096, 2),
    ('circularize', 2, 1),
    ('circularize', 4, 1),
  ];
  for (final item in cases) {
    test('DP111 ${item.$1}/${item.$2} 分档、双语、同值去重及恢复配对', () {
      final log = MowerMachineLog();
      addTearDown(log.dispose);
      log.apply(_fault(_alarm()), snapshot: true, receivedAt: _time);
      final active = {..._alarm(), item.$1: item.$2};
      log.apply(_fault(active), receivedAt: _time);
      expect(log.entries, hasLength(1));
      expect(log.entries.single.level, item.$3);
      expect(log.entries.single.message(false), isNotEmpty);
      expect(log.entries.single.message(true), isNotEmpty);
      log.apply(
        _fault(active),
        receivedAt: _time.add(const Duration(seconds: 60)),
      );
      expect(log.entries, hasLength(1));
      log.apply(
        _fault(_alarm()),
        receivedAt: _time.add(const Duration(seconds: 61)),
      );
      expect(log.entries, hasLength(1));
      expect(log.entries.single.recovered, isTrue);
      expect(log.entries.single.level, 1);
      expect(log.entries.single.message(false), contains('已恢复'));
      expect(log.entries.single.message(true), contains('cleared'));
      expect(log.unreadCritical, 0);
    });
  }
  test('日志掩码全覆盖，DP18/死位/工况位不入日志', () {
    expect(
      MowerMachineLog.noticeMask |
          MowerMachineLog.minorMask |
          MowerMachineLog.skipMask,
      0xfffff,
    );
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply({
      18: 8191,
      111: jsonEncode(
        _alarm(
          device: 64,
          error: 512 | 8192,
          circularize: MowerMachineLog.skipMask,
        ),
      ),
    }, receivedAt: _time);
    expect(log.entries, isEmpty);
  });
  test('查询与重连快照不制造日志；静置重报五分钟不刷屏', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    final packet = {
      5: 'mowing',
      111: jsonEncode(_alarm(error: 2)),
      13: 30,
      117: 'charging',
      118: false,
      113: true,
    };
    log.apply(packet, snapshot: true, receivedAt: _time);
    for (var i = 0; i < 300; i++) {
      log.apply(packet, receivedAt: _time.add(Duration(seconds: i)));
    }
    expect(log.entries, isEmpty);
  });
  test('DP5故障与具体DP111合并，同帧解除后原条目恢复且不计红点', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply(
      {5: 'standby', 111: jsonEncode(_alarm())},
      snapshot: true,
      receivedAt: _time,
    );
    log.apply({
      5: 'fault',
      111: jsonEncode(_alarm(error: 2)),
    }, receivedAt: _time);
    expect(log.entries, hasLength(1));
    expect(log.entries.single.message(false), '机器被抬起，已停机');
    log.apply(
      _fault(_alarm()),
      receivedAt: _time.add(const Duration(seconds: 1)),
    );
    expect(log.entries.single.recovered, isTrue);
    expect(log.unreadCritical, 0);
  });
  test('抬起轻微升级严重仍一条，恢复时不留下同事故红点', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply(_fault(_alarm(circularize: 4096)), receivedAt: _time);
    log.apply(
      _fault(_alarm(error: 2, circularize: 4096)),
      receivedAt: _time.add(const Duration(seconds: 12)),
    );
    expect(log.entries, hasLength(1));
    expect(log.entries.single.level, 3);
    expect(log.entries.single.message(false), '机器被抬起，已停机');
    log.apply(
      _fault(_alarm()),
      receivedAt: _time.add(const Duration(seconds: 13)),
    );
    expect(log.entries.single.recovered, isTrue);
  });
  test('严重降档30秒、轻微降档60秒，日志恢复立即生效', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply(_fault(_alarm(error: 1)), receivedAt: _time);
    log.apply(
      _fault(_alarm()),
      receivedAt: _time.add(const Duration(seconds: 1)),
    );
    expect(log.levelAt(_time.add(const Duration(seconds: 29))), 3);
    expect(log.levelAt(_time.add(const Duration(seconds: 31))), 0);
    expect(log.entries.single.recovered, isTrue);
    log.apply(
      _fault(_alarm(circularize: 16)),
      receivedAt: _time.add(const Duration(seconds: 40)),
    );
    log.apply(
      _fault(_alarm()),
      receivedAt: _time.add(const Duration(seconds: 41)),
    );
    expect(log.levelAt(_time.add(const Duration(seconds: 99))), 2);
    expect(log.levelAt(_time.add(const Duration(seconds: 101))), 0);
  });
  test('弱信号抖动60秒合并成同一条，恢复仍即时配对', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply(_fault(_alarm(circularize: 16)), receivedAt: _time);
    log.apply(
      _fault(_alarm()),
      receivedAt: _time.add(const Duration(seconds: 10)),
    );
    log.apply(
      _fault(_alarm(circularize: 16)),
      receivedAt: _time.add(const Duration(seconds: 20)),
    );
    expect(log.entries, hasLength(1));
    expect(log.entries.single.recovered, isFalse);
  });
  test('6个必需DP按边沿：开关盖、35%低电、关机连发、充电离桩', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply(
      {5: 'standby', 13: 40, 117: 0, 118: true, 113: false},
      snapshot: true,
      receivedAt: _time,
    );
    log.apply({118: false, 13: 35, 117: 1, 113: true}, receivedAt: _time);
    expect(log.entries, hasLength(4));
    for (var i = 0; i < 9; i++) {
      log.apply({113: true, 13: 34, 117: 1}, receivedAt: _time);
    }
    expect(log.entries, hasLength(4));
    log.apply({118: true, 117: 2, 113: false}, receivedAt: _time);
    log.apply({117: 0}, receivedAt: _time);
    expect(
      log.entries.map((e) => e.message(false)),
      containsAll(['机器盖子被打开', '机器盖子已关闭', '设备已关机', '设备已开机', '充电完成', '机器已离开充电桩']),
    );
  });
  test('正常作业边沿、回充、在桩等待不刷屏，DP5休眠不是关机', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply({5: 0}, snapshot: true, receivedAt: _time);
    for (final status in [1, 4, 9, 9, 2]) {
      log.apply({5: status}, receivedAt: _time);
    }
    expect(log.entries.map((e) => e.message(false)), [
      '机器已回到充电桩',
      '作业结束，正在返回充电桩',
      '开始割草',
    ]);
  });
  test('DP115 seq重复去重，回绕合法，成功不记，26等新鲜111定位', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    void command(int code, int seq) => log.apply({
      115: jsonEncode({'code': code, 'seq': seq, 'dp': 3, 'val': 1}),
    }, receivedAt: _time);
    log.apply(_fault(_alarm(device: 1)), snapshot: true, receivedAt: _time);
    command(26, 255);
    expect(log.entries.single.message(false), contains('暂未收到'));
    command(26, 255);
    expect(log.entries, hasLength(1));
    log.apply(
      _fault(_alarm(error: 4)),
      receivedAt: _time.add(const Duration(seconds: 1)),
    );
    final rejection = log.entries.firstWhere((e) => e.group == 'command');
    expect(rejection.message(false), contains('边界线供电'));
    expect(rejection.message(false), isNot(contains('电池异常')));
    expect(rejection.message(true), contains('Boundary signal'));
    command(255, 0);
    expect(log.entries.first.message(false), '操作未生效');
    final count = log.entries.length;
    command(0, 1);
    expect(log.entries, hasLength(count));
  });
  test('本机存储往返，已读、恢复和双语保留，容量有界、损坏条目不崩溃', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    for (var i = 0; i < 210; i++) {
      log.apply({
        5: i.isEven ? 1 : 0,
      }, receivedAt: _time.add(Duration(seconds: i)));
    }
    expect(log.entries, hasLength(200));
    log.markRead();
    final restored = MowerMachineLog();
    addTearDown(restored.dispose);
    restored.restore(log.encode());
    expect(restored.entries, hasLength(200));
    expect(restored.entries.every((e) => e.read), isTrue);
    expect(restored.entries.first.message(true), isNotEmpty);
    final bad = MowerMachineLog();
    addTearDown(bad.dispose);
    bad.restore('{');
    bad.restore('{"version":1,"entries":[{}]}');
    expect(bad.entries, isEmpty);
  });
  test('容量淘汰保留未恢复故障，后续清位可配对恢复', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply(_fault(_alarm(device: 1)), receivedAt: _time);
    final faultId = log.entries.single.id;
    for (var i = 0; i < 210; i++) {
      log.apply({
        5: i.isEven ? 1 : 0,
      }, receivedAt: _time.add(Duration(seconds: i + 3)));
    }
    expect(log.entries, hasLength(200));
    expect(
      log.entries.any((e) => e.id == faultId && e.active.isNotEmpty),
      isTrue,
    );
    log.apply(
      _fault(_alarm()),
      receivedAt: _time.add(const Duration(seconds: 300)),
    );
    final recovered = log.entries.firstWhere((e) => e.id == faultId);
    expect(recovered.recovered, isTrue);
    expect(recovered.level, 1);
  });
  test('合并事故严重原因清除后降为剩余轻微，不保留错误告警红点', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply(_fault(_alarm(device: 1, circularize: 16)), receivedAt: _time);
    expect(log.entries.single.level, 3);
    log.apply(
      _fault(_alarm(circularize: 16)),
      receivedAt: _time.add(const Duration(seconds: 1)),
    );
    expect(log.entries.single.level, 2);
    expect(log.entries.single.recovered, isFalse);
    expect(log.entries.single.message(false), contains('电池异常已恢复'));
    expect(log.unreadCritical, 0);
    log.apply(
      _fault(_alarm()),
      receivedAt: _time.add(const Duration(seconds: 2)),
    );
    expect(log.entries.single.level, 1);
    expect(log.entries.single.recovered, isTrue);
  });
  test('code26日志等待过期后不会用迟到111修改那次拒绝详情', () {
    final log = MowerMachineLog();
    addTearDown(log.dispose);
    log.apply({115: '{"code":26,"seq":1,"dp":3}'}, receivedAt: _time);
    log.apply(
      _fault(_alarm(device: 1)),
      receivedAt: _time.add(const Duration(milliseconds: 3500)),
    );
    expect(
      log.entries.firstWhere((e) => e.group == 'command').message(false),
      contains('暂未收到最新故障详情'),
    );
  });
}
