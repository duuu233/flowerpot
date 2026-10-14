import 'dart:typed_data';
import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flutter_test/flutter_test.dart';

/// 割草机 DP 编解码的回归用例（2026-09-18 接线）。
///
/// 锁的是「错了也不会报错、只是设备按另一套跑」的那几处：
///   ① DP101 是 **88 字节 = 8 组 × 11**，组 0~6=**周一~周日**、组7备用，
///      而界面用的是「日一二三四五六」——两者差一位，换算错了整周计划就整体错开一天；
///   ② 时间是 **uint16 小端**，大端写进去设备会解成完全不同的时刻；
///   ③ 周一组0不能冒充整周，复制整周必须写七个星期组与沿边位；
///   ④ DP103 的百分比 0 = 删除该区，valid 位必须跟着给 0。
void main() {
  test('V2.6空时段的整周修边写满七天，备用组零；回读保留沿边位', () {
    final data = MowerScheduleCodec.encodeAll(
      const MowerScheduleDay(edge: true),
    );
    for (var group = 0; group < 7; group++) {
      expect(data.sublist(group * 11, group * 11 + 8), everyElement(0));
      expect(data[group * 11 + 8], 1);
      expect(data[group * 11 + 9], 0);
      expect(data[group * 11 + 10], 0);
    }
    expect(data.sublist(77), everyElement(0));
    expect(MowerScheduleCodec.decode(data).every((day) => day.edge), isTrue);
  });
  test('V2.6备用组不覆盖七天，日志明确标周一/周日/备用', () {
    final data = Uint8List(88);
    data.setRange(77, 88, [0x1c, 0x02, 0xd0, 0x02, 0, 0, 0, 0, 1, 1, 0]);
    expect(
      MowerScheduleCodec.decode(data).every((day) => day.isEmpty && !day.edge),
      isTrue,
    );
    final lines = MowerScheduleCodec.describe(data);
    expect(lines[1], startsWith('组0 周一'));
    expect(lines[7], startsWith('组6 周日'));
    expect(lines[8], startsWith('组7 备用'));
  });

  test('V2.6固定周一~周五示例解码，周末空；周一不能当全部设置', () {
    final raw = <int>[
      for (var day = 0; day < 5; day++) ...[
        0x1c,
        0x02,
        0xd0,
        0x02,
        0x48,
        0x03,
        0x38,
        0x04,
        1,
        1,
        1,
      ],
      ...List<int>.filled(33, 0),
    ];
    final decoded = MowerScheduleCodec.decode(Uint8List.fromList(raw));
    expect(decoded[0].slotOne, isNull, reason: '周日组6为空');
    expect(decoded[6].slotOne, isNull, reason: '周六组5为空');
    for (var day = 1; day <= 5; day++) {
      expect(decoded[day].edge, isTrue);
      expect(decoded[day].slotOne?.startMinutes, 540);
      expect(decoded[day].slotTwo?.endMinutes, 1080);
    }
    expect(MowerScheduleCodec.encodeByDay(decoded), raw);
  });

  group('DP101 割草计划', () {
    test('按天编码：周日落在组 6，时间是小端', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      // 界面序 0 = 周日 → DP 组 6
      week[0] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 540, endMinutes: 660),
      );
      final data = MowerScheduleCodec.encodeByDay(week);

      expect(data.length, 88);
      // 组7备用，明确留零
      expect(data.sublist(77, 88), everyElement(0));

      const offset = 6 * MowerScheduleCodec.groupSize;
      expect(data[offset], 540 & 0xFF, reason: '开始时间低字节在前（小端）');
      expect(data[offset + 1], 540 >> 8);
      expect(data[offset + 2], 660 & 0xFF);
      expect(data[offset + 3], 660 >> 8);
      expect(data[offset + 9], 1, reason: '时段 1 有效位');
      expect(data[offset + 10], 0, reason: '没有时段 2');
    });

    test('周一落在组0，不是全部设置', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      week[1] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 480, endMinutes: 600),
      );
      final data = MowerScheduleCodec.encodeByDay(week);
      expect(data[9], 1);
      expect(data.sublist(77, 88), everyElement(0));
    });

    test('时长不足 10 分钟的时段不编进去（设备会丢弃）', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      week[2] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 600, endMinutes: 609),
      );
      final data = MowerScheduleCodec.encodeByDay(week);
      final offset = 1 * MowerScheduleCodec.groupSize;
      expect(data[offset + 9], 0, reason: '9 分钟的时段不该带有效位');
    });

    test('关掉的时段（总开关 off）有效位 0，但起止照写，解回来是关着的时段', () {
      // 2026-10-08：停用的时段设备不执行，但回显回来还要认得出时间，再启用才能原样回来。
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      week[3] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(
          startMinutes: 540,
          endMinutes: 660,
          enabled: false,
        ),
        slotTwo: MowerScheduleSlot(startMinutes: 900, endMinutes: 960),
      );
      final data = MowerScheduleCodec.encodeByDay(week);
      final offset = 2 * MowerScheduleCodec.groupSize;
      expect(data[offset + 9], 0, reason: '停用的时段设备不能执行');
      expect(data[offset] | (data[offset + 1] << 8), 540);
      expect(data[offset + 2] | (data[offset + 3] << 8), 660);
      expect(data[offset + 10], 1);

      final decoded = MowerScheduleCodec.decode(data)[3];
      expect(decoded.slotOne?.enabled, isFalse);
      expect(decoded.slotOne?.startMinutes, 540);
      expect(decoded.slotOne?.endMinutes, 660);
      expect(decoded.slotTwo?.enabled, isTrue);
      expect(decoded.isEmpty, isFalse);
    });

    test('还没排的空时段（关着的 00:00–00:00）照旧整段写 0，解回来是没有', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      week[1] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(
          startMinutes: 0,
          endMinutes: 0,
          enabled: false,
        ),
      );
      final data = MowerScheduleCodec.encodeByDay(week);
      expect(data.sublist(0, MowerScheduleCodec.groupSize), everyElement(0));
      expect(MowerScheduleCodec.decode(data)[1].slotOne, isNull);
    });

    test('编码再解码，时间与修边都还原', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      week[4] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 900, endMinutes: 983),
        slotTwo: MowerScheduleSlot(startMinutes: 1200, endMinutes: 1320),
        edge: true,
      );
      final decoded = MowerScheduleCodec.decode(
        MowerScheduleCodec.encodeByDay(week),
      );
      expect(decoded[4].slotOne?.startMinutes, 900);
      expect(decoded[4].slotOne?.endMinutes, 983);
      expect(decoded[4].slotTwo?.startMinutes, 1200);
      expect(decoded[4].edge, isTrue);
      expect(decoded[5].slotOne, isNull);
    });

    test('整周相同明确写七个组，备用留零，解回七天', () {
      final data = MowerScheduleCodec.encodeAll(
        const MowerScheduleDay(
          slotOne: MowerScheduleSlot(startMinutes: 540, endMinutes: 660),
        ),
      );
      final decoded = MowerScheduleCodec.decode(data);
      expect(decoded, hasLength(7));
      for (final day in decoded) {
        expect(day.slotOne?.startMinutes, 540);
      }
    });

    test('两个时段相交算重叠，端点相接不算', () {
      const overlap = MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 540, endMinutes: 690),
        slotTwo: MowerScheduleSlot(startMinutes: 600, endMinutes: 720),
      );
      expect(overlap.overlapMessage, isNotNull);

      const touching = MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 540, endMinutes: 690),
        slotTwo: MowerScheduleSlot(startMinutes: 690, endMinutes: 720),
      );
      expect(touching.overlapMessage, isNull, reason: '前一段结束＝后一段开始是「接着干」，不该拦');
    });
  });

  group('DP103 区域配置', () {
    test('25 字节，距离小端，百分比 0 的区 valid 也给 0', () {
      final data = MowerZoneCodec.encode(const <MowerZoneConfig>[
        MowerZoneConfig(index: 1, percent: 30, meters: 300),
        MowerZoneConfig(index: 2, percent: 0, meters: 50),
      ]);
      expect(data.length, 25);
      expect(data[0], 1);
      expect(data[1], 30);
      // 300 超过设备上限 200，编码时钳住
      expect(data[2] | (data[3] << 8), MowerZoneCodec.maxMeters);
      expect(data[4], 1);
      expect(data[6], 0, reason: '百分比 0 = 删区');
      expect(data[9], 0, reason: '百分比 0 时 valid 必须跟着 0');
    });
  });

  group('枚举', () {
    test('DP3 只有前四个能下发', () {
      expect(MowerMode.smart.sendable, isTrue);
      expect(MowerMode.gotoCharge.sendable, isTrue);
      expect(MowerMode.edgeMowing.sendable, isFalse);
      expect(MowerMode.waitRain.sendable, isFalse);
    });

    test('DP3 的枚举序：smart=1 / spot=2 / goto_charge=3（按枚举值列表，不是 xlsx 说明列）', () {
      expect(MowerMode.standby.value, 0);
      expect(MowerMode.smart.value, 1);
      expect(MowerMode.spot.value, 2);
      expect(MowerMode.gotoCharge.value, 3);
    });

    test('DP107 时区：20 = UTC+8', () {
      expect(MowerTimezone.codeOf(20), 'UTCB8');
      expect(MowerTimezone.codeOf(12), 'UTCB0');
      expect(MowerTimezone.codeOf(0), 'UTCA12');
      expect(MowerTimezone.fromDeviceOffset(const Duration(hours: 8)), 20);
    });

    test('DP109 没有中文，简中手机落到 english', () {
      expect(MowerLanguage.forLocale('zh'), MowerLanguage.english);
      expect(MowerLanguage.forLocale('de'), MowerLanguage.german);
      expect(MowerLanguage.values, hasLength(18));
    });

    test('DP18 位图取最低位那条文案', () {
      expect(MowerFault.firstMessage(0), isNull);
      expect(MowerFault.firstMessage(1 << 3), '机器翻倒，请将其扶正放平。');
      expect(
        MowerFault.firstMessage((1 << 3) | (1 << 1)),
        '右轮异常，请清理异物并重启。',
        reason: '多个故障同时置位时按位序取第一个',
      );
      expect(MowerFault.activeIdentifiers((1 << 0) | (1 << 12)), <String>[
        'left_wheel',
        'blade_motor',
      ]);
    });
  });

  // 2026-09-21 接真机：上报方向的解码。
  group('上报解码（接真机）', () {
    test('DP103 区域：与编码对称；百分比 0 / valid=0 的区解成 0%', () {
      const zones = <MowerZoneConfig>[
        MowerZoneConfig(index: 1, percent: 30, meters: 12),
        MowerZoneConfig(index: 3, percent: 0, meters: 99),
        MowerZoneConfig(index: 5, percent: 70, meters: 200),
      ];
      final decoded = MowerZoneCodec.decode(MowerZoneCodec.encode(zones));
      expect(decoded.map((zone) => zone.index), <int>[1, 2, 3, 4, 5]);
      expect(decoded.map((zone) => zone.percent), <int>[30, 0, 0, 0, 70]);
      expect(decoded[0].meters, 12);
      expect(decoded[4].meters, 200, reason: '距离是 uint16 小端，200 要原样回来');
    });

    test('DP103 区域：长度不够的区照样给一行 0%，页面能画满 5 行', () {
      final decoded = MowerZoneCodec.decode(<int>[1, 50, 10, 0, 1]);
      expect(decoded, hasLength(5));
      expect(decoded[0].percent, 50);
      expect(decoded.skip(1).every((zone) => zone.percent == 0), isTrue);
    });

    test('DP107 时区：UTCB 是正偏移、UTCA 是负偏移，和 codeOf 互逆', () {
      expect(MowerTimezone.indexOfCode('UTCB8'), MowerTimezone.zeroIndex + 8);
      expect(MowerTimezone.indexOfCode('UTCA5'), MowerTimezone.zeroIndex - 5);
      expect(MowerTimezone.indexOfCode('UTCB0'), MowerTimezone.zeroIndex);
      for (var index = 0; index < MowerTimezone.count; index++) {
        expect(MowerTimezone.indexOfCode(MowerTimezone.codeOf(index)), index);
      }
      expect(MowerTimezone.indexOfCode('UTCB13'), isNull);
      expect(MowerTimezone.indexOfCode('beijing'), isNull);
      expect(MowerTimezone.indexOfCode(20), 20, reason: '个别桥接直接报序号');
    });

    test('枚举型 DP：认字符串，也认序号；认不出返回 null', () {
      String code(MowerMode mode) => mode.code;
      expect(MowerDp.enumOf(MowerMode.values, code, 'spot'), MowerMode.spot);
      expect(MowerDp.enumOf(MowerMode.values, code, 3), MowerMode.gotoCharge);
      expect(MowerDp.enumOf(MowerMode.values, code, 'random'), isNull);
      expect(MowerDp.enumOf(MowerMode.values, code, 99), isNull);
    });
  });

  group('DP101 逐字节解析（联调对比用，2026-09-23）', () {
    test('V2.6只填组0：只设置周一09:00–11:00，不覆盖其他天', () {
      final data = List<int>.filled(MowerScheduleCodec.bytes, 0);
      data.setRange(0, 11, <int>[0x1C, 0x02, 0x94, 0x02, 0, 0, 0, 0, 0, 1, 0]);

      final lines = MowerScheduleCodec.describe(data);

      expect(lines.first, contains('V2.6 按天设置'));
      expect(lines[1], startsWith('组0 周一：时段1 09:00–11:00；'));
      expect(lines[1], contains('时段2 00:00–00:00（无效）'));
      expect(lines.skip(2), everyElement(endsWith('全 00')));
    });

    test('V2.6协议示例2：填组0和组1 → 按天设置；≤10 分钟和长度不对都会标出来', () {
      final data = List<int>.filled(MowerScheduleCodec.bytes, 0);
      data.setRange(0, 11, <int>[0xE0, 0x01, 0x58, 0x02, 0, 0, 0, 0, 0, 1, 0]);
      // 周二（组 1）放一个 5 分钟的时段：设备会丢弃
      data.setRange(11, 22, <int>[0xE0, 0x01, 0xE5, 0x01, 0, 0, 0, 0, 1, 1, 0]);

      final lines = MowerScheduleCodec.describe(data);

      expect(lines.first, contains('按天设置'));
      expect(lines[1], startsWith('组0 周一：时段1 08:00–10:00；'));
      expect(lines[2], contains('≤10 分钟，设备会丢弃'));
      expect(lines[2], contains('沿边=1'));
      expect(
        MowerScheduleCodec.describe(<int>[1, 2, 3]).single,
        contains('不按 DP101 解析'),
      );
    });
  });
}
