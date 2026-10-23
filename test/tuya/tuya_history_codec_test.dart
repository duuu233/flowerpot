import 'dart:convert';

import 'package:flowerpot/src/features/devices/models/history_period.dart';
import 'package:flowerpot/src/tuya/tuya_history_codec.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 帧格式以产品《app_DP_问题修正说明》§4 为准：日帧 3 字节头（年偏移 月 日），
/// 周帧 4 字节头（+ 点数），月帧 5 字节头（+ 段号 总段数）。

String _payload(List<int> bytes) => base64.encode(bytes);

/// 一个日帧：2026-[month]-[day]，[count] 个 1 字节点（值 = 下标 % 201）。
List<int> _day(int month, int day, int count) => <int>[
  26,
  month,
  day,
  for (var i = 0; i < count; i++) i % 201,
];

HistoryDayFrame? _decodeDay(List<int> bytes) =>
    TuyaHistoryCodec.decodeDayFrame(bytes, sampleBytes: 1);

HistoryDayFrame _dayFrame(int month, int day, int count) =>
    _decodeDay(_day(month, day, count))!;

void main() {
  group('日帧', () {
    test('过去的一天：3 字节头 + 96 个 1 字节点', () {
      final frame = TuyaHistoryCodec.decodeDayFrame(
        _payload(_day(10, 20, 96)),
        sampleBytes: 1,
      )!;

      expect(frame.date, DateTime(2026, 10, 20));
      expect(frame.dayKey, '10-20');
      expect(frame.samples, hasLength(96));
      expect(frame.samples.last, 95);
    });

    test('今天那帧变长：点数由帧长反推，不写死 96', () {
      expect(_decodeDay(_day(10, 23, 41))!.samples, hasLength(41));
    });

    test('光照 2 字节大端；空气温度 2 字节有符号（支持负温）', () {
      expect(
        TuyaHistoryCodec.decodeDayFrame(<int>[
          26, 10, 23, 0x23, 0x28, 0x00, 0x64, //
        ], sampleBytes: 2)!.samples,
        <double>[9000, 100],
      );
      // 0xFF9C = -100（即 -10.0 °C，÷10 在仓库里做），0x00FA = 250。
      expect(
        TuyaHistoryCodec.decodeDayFrame(
          <int>[26, 10, 23, 0xFF, 0x9C, 0x00, 0xFA],
          sampleBytes: 2,
          signed: true,
        )!.samples,
        <double>[-100, 250],
      );
    });

    test('帧长与帧头矛盾、日期不合法、超过 96 点的都丢弃', () {
      for (final bytes in <List<int>>[
        <int>[26, 10, 23], // 没有点
        _day(13, 1, 4), // 13 月
        _day(2, 30, 4), // 2 月 30
        _day(10, 23, 97), // 超过一天的槽数
      ]) {
        expect(_decodeDay(bytes), isNull, reason: '$bytes');
      }
      // 2 字节点却多出半个。
      expect(
        TuyaHistoryCodec.decodeDayFrame(<int>[
          26, 10, 23, 0x00, 0x64, 0x01, //
        ], sampleBytes: 2),
        isNull,
      );
    });

    test('未对时帧（2026-01-01 且只有 1 个点）丢弃；两个条件缺一不丢', () {
      expect(_decodeDay(_day(1, 1, 1)), isNull);
      expect(_decodeDay(_day(1, 1, 2)), isNotNull);
      expect(_decodeDay(_day(1, 2, 1)), isNotNull);
    });

    test('SDK 的十六进制串和 base64 解出来一样', () {
      final bytes = _day(10, 20, 96);
      final hex = bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();

      expect(
        TuyaHistoryCodec.decodeDayFrame(hex, sampleBytes: 1)!.samples,
        TuyaHistoryCodec.decodeDayFrame(
          _payload(bytes),
          sampleBytes: 1,
        )!.samples,
      );
    });
  });

  group('周帧', () {
    test('点数取帧头第 4 字节，最多 28', () {
      final frame = TuyaHistoryCodec.decodeWeekFrame(<int>[
        26,
        10,
        22,
        28,
        for (var i = 1; i <= 28; i++) i,
      ], sampleBytes: 1)!;

      expect(frame.samples, hasLength(28));
      expect(frame.samples.last, 28);
    });

    test('帧长对不上点数、N = 0、N > 28 都丢弃', () {
      for (final bytes in <List<int>>[
        <int>[26, 10, 22, 7, 10, 20], // 说 7 个只给了 2 个
        <int>[26, 10, 22, 0],
        <int>[26, 10, 22, 29, for (var i = 0; i < 29; i++) i],
      ]) {
        expect(
          TuyaHistoryCodec.decodeWeekFrame(bytes, sampleBytes: 1),
          isNull,
          reason: '$bytes',
        );
      }
    });
  });

  group('月帧', () {
    test('5 字节头：段号、总段数，点数由帧长推', () {
      final segment = TuyaHistoryCodec.decodeMonthSegment(<int>[
        26, 10, 22, 1, 2, 91, 92, 93, //
      ], sampleBytes: 1)!;

      expect(segment.index, 1);
      expect(segment.total, 2);
      expect(segment.samples, <double>[91, 92, 93]);
    });

    test('段号越界、总段数 0 或 > 2、单段超过 90 点的丢弃', () {
      for (final bytes in <List<int>>[
        <int>[26, 10, 22, 2, 2, 1],
        <int>[26, 10, 22, 0, 0, 1],
        <int>[26, 10, 22, 0, 3, 1],
        <int>[26, 10, 22, 0, 2, for (var i = 0; i < 91; i++) 1],
      ]) {
        expect(
          TuyaHistoryCodec.decodeMonthSegment(bytes, sampleBytes: 1),
          isNull,
          reason: '$bytes',
        );
      }
    });
  });

  group('HistoryFrameBuffer', () {
    const id = 'tank_level_daily_hist';

    test('7 个日帧按帧头日期归档，最新日期那帧才是今天（不是最后到的那帧）', () {
      final buffer = HistoryFrameBuffer()..addDay(id, _dayFrame(10, 23, 41));
      // 设备一次全量上报连发 7 帧，最后到的往往是 6 天前。
      for (var day = 22; day >= 17; day--) {
        buffer.addDay(id, _dayFrame(10, day, 96));
      }

      final days = buffer.days(id);
      expect(days.map((day) => day.dayKey), <String>[
        '10-17',
        '10-18',
        '10-19',
        '10-20',
        '10-21',
        '10-22',
        '10-23',
      ]);
      expect(days.last.samples, hasLength(41));
    });

    test('今天那帧随时间变长：同一天整块替换', () {
      final buffer = HistoryFrameBuffer()
        ..addDay(id, _dayFrame(10, 23, 41))
        ..addDay(id, _dayFrame(10, 23, 42));

      expect(buffer.days(id).single.samples, hasLength(42));
    });

    test('只留最新那天往前 7 天', () {
      final buffer = HistoryFrameBuffer()
        ..addDay(id, _dayFrame(10, 16, 96))
        ..addDay(id, _dayFrame(10, 23, 10));

      expect(buffer.days(id).map((day) => day.dayKey), <String>['10-23']);
    });

    test('过去的日帧必须满 96 点：早于昨天还不满的丢弃', () {
      final buffer = HistoryFrameBuffer()
        ..addDay(id, _dayFrame(10, 23, 41))
        ..addDay(id, _dayFrame(10, 18, 1))
        ..addDay(id, _dayFrame(10, 19, 96));

      expect(buffer.days(id).map((day) => day.dayKey), <String>[
        '10-19',
        '10-23',
      ]);
    });

    test('先收到的短帧，等更新的日期来了就不再是今天，一样丢', () {
      final buffer = HistoryFrameBuffer()
        ..addDay(id, _dayFrame(10, 20, 30))
        ..addDay(id, _dayFrame(10, 23, 41));

      expect(buffer.days(id).map((day) => day.dayKey), <String>['10-23']);
    });

    test('跨 0 点：昨天那份没满 96 点先留着（0 点全量会补来满的）', () {
      final buffer = HistoryFrameBuffer()
        ..addDay(id, _dayFrame(10, 22, 95))
        ..addDay(id, _dayFrame(10, 23, 1));

      expect(buffer.days(id).first.samples, hasLength(95));
      expect(buffer.days(id).last.samples, hasLength(1));
    });

    test('月段按段号拼，没收齐先用已到的段；期变了重攒', () {
      HistoryMonthSegment segment(
        int index,
        int total,
        List<int> points, {
        int day = 22,
      }) => TuyaHistoryCodec.decodeMonthSegment(<int>[
        26,
        10,
        day,
        index,
        total,
        ...points,
      ], sampleBytes: 1)!;
      const month = 'tank_level_monthly_hist';
      final buffer = HistoryFrameBuffer()
        ..addMonth(month, segment(1, 2, <int>[3, 4]));

      expect(buffer.month(month), <double>[3, 4]);
      expect(buffer.monthComplete(month), isFalse);

      buffer.addMonth(month, segment(0, 2, <int>[1, 2]));
      expect(buffer.month(month), <double>[1, 2, 3, 4]);
      expect(buffer.monthComplete(month), isTrue);

      // 只有 1 段的一期：收到就齐，不等第 2 段。
      buffer.addMonth(month, segment(0, 1, <int>[9], day: 23));
      expect(buffer.month(month), <double>[9]);
      expect(buffer.monthComplete(month), isTrue);
    });
  });

  group('没采到的点（以 0 补齐）', () {
    DeviceHistory history(Map<SensorMetric, List<double>> byMetric) =>
        DeviceHistory(
          const <String, List<double>>{},
          <String, Map<String, List<double>>>{
            for (final entry in byMetric.entries)
              entry.key.name: <String, List<double>>{'10-23': entry.value},
          },
          <String, String>{
            for (final metric in byMetric.keys) metric.name: '10-23',
          },
        );

    test('同一刻所有指标都是 0 才算没采到；夜里光照 0、水箱空了是真实读数', () {
      final gaps = history(<SensorMetric, List<double>>{
        SensorMetric.waterLevel: <double>[0, 0, 80, 0],
        SensorMetric.light: <double>[0, 0, 0, 120],
        SensorMetric.humidity: <double>[0, 55, 56, 57],
        SensorMetric.temperature: <double>[0, 21, 22, 23],
      }).latestDayGaps(SensorMetric.light);

      expect(gaps, <bool>[true, false, false, false]);
    });

    test('今天那几帧先后到：还没到的指标不参与，只有一个指标的那一格不下结论', () {
      final gaps = history(<SensorMetric, List<double>>{
        SensorMetric.waterLevel: <double>[0, 0, 0],
        SensorMetric.humidity: <double>[0],
      }).dayGaps(SensorMetric.waterLevel, DateTime(2026, 10, 23));

      expect(gaps, <bool>[true, false, false]);
    });

    test('没有这一天就没有标记', () {
      expect(
        history(<SensorMetric, List<double>>{
          SensorMetric.waterLevel: <double>[0],
        }).dayGaps(SensorMetric.waterLevel, DateTime(2026, 10, 22)),
        isEmpty,
      );
      expect(DeviceHistory.empty.latestDayGaps(SensorMetric.light), isEmpty);
    });
  });

  group('日视图横轴按时刻标整点', () {
    test('满 96 点的一天：00:00 起每 4 小时一个，落在对应的点上', () {
      final ticks = HistoryPeriod.timeTicks(<int>[
        for (var i = 0; i < 96; i++) i * 15,
      ]);

      expect(ticks.labels, <String>[
        '00:00',
        '04:00',
        '08:00',
        '12:00',
        '16:00',
        '20:00',
      ]);
      expect(ticks.positions, <double>[0, 16, 32, 48, 64, 80]);
    });

    test('今天上午 10 点只有 41 个点：刻度到 10:00 为止，不拉满 24 小时', () {
      final ticks = HistoryPeriod.timeTicks(<int>[
        for (var i = 0; i < 41; i++) i * 15,
      ]);

      expect(ticks.labels.first, '00:00');
      expect(ticks.labels.last, '10:00');
      expect(ticks.positions.last, 40);
    });

    test('实时点按收到的时刻插值：10:00 的包后面 10:10 收到一个点', () {
      final ticks = HistoryPeriod.timeTicks(<int>[
        540,
        555,
        570,
        585,
        600,
        610,
      ]);

      expect(ticks.labels, <String>[
        '09:00',
        '09:15',
        '09:30',
        '09:45',
        '10:00',
      ]);
      expect(ticks.positions.last, 4);
    });

    test('只有一个点、跨过 0 点的钟点', () {
      final single = HistoryPeriod.timeTicks(<int>[615]);
      expect(single.labels, <String>['10:15']);
      expect(single.positions, <double>[0]);
      expect(HistoryPeriod.clockLabel(1440 + 5), '00:05');
      expect(HistoryPeriod.timeTicks(const <int>[]).labels, isEmpty);
    });
  });
}
