import 'package:flowerpot/src/features/mower/mower_dp.dart';
import 'package:flutter_test/flutter_test.dart';

/// 割草机 DP 编解码的回归用例（2026-09-18 接线）。
///
/// 锁的是「错了也不会报错、只是设备按另一套跑」的那几处：
///   ① DP101 是 **88 字节 = 8 组 × 11**，组 0=全部设置、组 1~7=**周一~周日**，
///      而界面用的是「日一二三四五六」——两者差一位，换算错了整周计划就整体错开一天；
///   ② 时间是 **uint16 小端**，大端写进去设备会解成完全不同的时刻；
///   ③ 「全部设置」（组 0 有效）解回来要摊成 7 天，否则界面一根色块都不画；
///   ④ DP103 的百分比 0 = 删除该区，valid 位必须跟着给 0。
void main() {
  group('DP101 割草计划', () {
    test('按天编码：周日落在组 7，时间是小端', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      // 界面序 0 = 周日 → DP 组 7
      week[0] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 540, endMinutes: 660),
      );
      final data = MowerScheduleCodec.encodeByDay(week);

      expect(data.length, 88);
      // 组 0（全部设置）必须留空，否则设备会以组 0 为准、把按天的全忽略
      expect(data.sublist(0, 11), everyElement(0));

      const offset = 7 * MowerScheduleCodec.groupSize;
      expect(data[offset], 540 & 0xFF, reason: '开始时间低字节在前（小端）');
      expect(data[offset + 1], 540 >> 8);
      expect(data[offset + 2], 660 & 0xFF);
      expect(data[offset + 3], 660 >> 8);
      expect(data[offset + 9], 1, reason: '时段 1 有效位');
      expect(data[offset + 10], 0, reason: '没有时段 2');
    });

    test('周一落在组 1（不是组 0）', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      week[1] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 480, endMinutes: 600),
      );
      final data = MowerScheduleCodec.encodeByDay(week);
      expect(data[MowerScheduleCodec.groupSize + 9], 1);
      expect(data.sublist(0, 11), everyElement(0));
    });

    test('时长不足 10 分钟的时段不编进去（设备会丢弃）', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      week[2] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(startMinutes: 600, endMinutes: 609),
      );
      final data = MowerScheduleCodec.encodeByDay(week);
      final offset = 2 * MowerScheduleCodec.groupSize;
      expect(data[offset + 9], 0, reason: '9 分钟的时段不该带有效位');
    });

    test('关掉的时段（总开关 off）不下发', () {
      final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
      week[3] = const MowerScheduleDay(
        slotOne: MowerScheduleSlot(
          startMinutes: 540,
          endMinutes: 660,
          enabled: false,
        ),
      );
      final data = MowerScheduleCodec.encodeByDay(week);
      final offset = 3 * MowerScheduleCodec.groupSize;
      expect(data[offset + 9], 0);
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

    test('「全部设置」解回来要摊成 7 天', () {
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
      expect(
        touching.overlapMessage,
        isNull,
        reason: '前一段结束＝后一段开始是「接着干」，不该拦',
      );
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
      expect(
        MowerTimezone.fromDeviceOffset(const Duration(hours: 8)),
        20,
      );
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
}
