import 'dart:convert';

import 'package:flowerpot/src/tuya/tuya_history_codec.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Year offset from 2000, month, day — the header every packet starts with.
const _dayHeader = <int>[26, 8, 20];

String _payload(List<int> bytes) => base64.encode(bytes);

void main() {
  test('a day packet decodes 96 single-byte samples', () {
    final samples = <int>[
      for (var i = 0; i < TuyaHistoryCodec.dailySamples; i++) i % 201,
    ];
    final decoded = TuyaHistoryCodec.decode(
      _payload(<int>[..._dayHeader, ...samples]),
      range: ReportRange.day,
      sampleBytes: 1,
    );

    expect(decoded.length, 96);
    expect(decoded.first, 0);
    expect(decoded[95], 95);
  });

  test('a day packet of light samples decodes two bytes big endian', () {
    final decoded = TuyaHistoryCodec.decode(
      _payload(<int>[..._dayHeader, 0x23, 0x28, 0x00, 0x64]),
      range: ReportRange.day,
      sampleBytes: 2,
    );

    // 0x2328 is 9000, the top of the light DP range.
    expect(decoded, <double>[9000, 100]);
  });

  test('week packets take their length from the count byte', () {
    final week = TuyaHistoryCodec.decode(
      _payload(<int>[26, 8, 14, 7, 10, 20, 30, 40, 50, 60, 70]),
      range: ReportRange.week,
      sampleBytes: 1,
    );
    expect(week, <double>[10, 20, 30, 40, 50, 60, 70]);

    // 设备端 1.0.13 起周帧的 N 是「环内有效天数 ≤ 28」（4 周的日均值），
    // 不是早期导出写的 7。字节位置没变，这里顺带钉一条满环的帧。
    final fourWeeks = TuyaHistoryCodec.decode(
      _payload(<int>[26, 9, 15, 28, for (var i = 1; i <= 28; i++) i]),
      range: ReportRange.week,
      sampleBytes: 1,
    );
    expect(fourWeeks.length, 28);
    expect(fourWeeks.last, 28);
  });

  /// 月帧：设备端 1.0.13 §2.4 把帧头改成 5 字节（年 月 日 **段号 总段数**），
  /// **没有点数字节**，点数由帧长推。
  ///
  /// 按旧口径（4 字节头 + 点数字节）解会把**段号当点数**：段 0 的 `bytes[3] == 0`
  /// ⇒ 解出 0 个点、月视图整条空白；段 1 ⇒ 只剩 1 个点。错得不报错，只有真机看得出来。
  group('月帧（1.0.13 的 5 字节头 + 分段）', () {
    test('段 0 满帧解出 90 个点——旧口径这里会是 0 个', () {
      final month = TuyaHistoryCodec.decode(
        _payload(<int>[
          26, 9, 15, 0, 2, //  年偏移 月 日 段号=0 总段数=2
          for (var i = 1; i <= 90; i++) i,
        ]),
        range: ReportRange.month,
        sampleBytes: 1,
      );
      expect(month.length, 90);
      expect(month.first, 1);
      expect(month.last, 90);
    });

    test('段 1 只带剩下那几天——旧口径这里只剩 1 个点', () {
      final month = TuyaHistoryCodec.decode(
        _payload(<int>[26, 9, 15, 1, 2, 91, 92, 93]),
        range: ReportRange.month,
        sampleBytes: 1,
      );
      expect(month, <double>[91, 92, 93]);
    });

    test('不满 90 天时只有段 0（总段数 1）', () {
      final month = TuyaHistoryCodec.decode(
        _payload(<int>[26, 9, 15, 0, 1, 11, 12, 13]),
        range: ReportRange.month,
        sampleBytes: 1,
      );
      expect(month, <double>[11, 12, 13]);
    });

    test('光照的月帧是 2 字节大端点', () {
      final month = TuyaHistoryCodec.decode(
        _payload(<int>[26, 9, 15, 0, 1, 0x0B, 0xB8, 0x00, 0x64]),
        range: ReportRange.month,
        sampleBytes: 2,
      );
      expect(month, <double>[3000, 100]);
    });

    test('段号与总段数能取出来，供以后拼接两段用', () {
      expect(
        TuyaHistoryCodec.monthSegment(
          _payload(<int>[26, 9, 15, 1, 2, 91, 92]),
        ),
        (1, 2),
      );
      // 段号越界 / 总段数为 0 的不认作段帧，避免把旧固件的月帧误判成分段。
      expect(
        TuyaHistoryCodec.monthSegment(_payload(<int>[26, 9, 15, 2, 2, 91])),
        isNull,
      );
      expect(
        TuyaHistoryCodec.monthSegment(_payload(<int>[26, 9, 15, 0, 0, 91])),
        isNull,
      );
    });
  });

  test('a packet shorter than its count byte claims is not padded', () {
    final decoded = TuyaHistoryCodec.decode(
      _payload(<int>[26, 8, 14, 7, 10, 20]),
      range: ReportRange.week,
      sampleBytes: 1,
    );

    expect(decoded, <double>[10, 20]);
  });

  test('an absent or unreadable payload reads as no history', () {
    for (final value in <Object?>[
      null,
      '',
      'not base64!!',
      <int>[26, 8, 20],
      _payload(<int>[26, 8, 14, 0]),
    ]) {
      expect(
        TuyaHistoryCodec.decode(
          value,
          range: ReportRange.week,
          sampleBytes: 1,
        ),
        isEmpty,
        reason: 'payload: $value',
      );
    }
  });

  test('SDK hex payloads decode the same as base64 ones', () {
    // 真机上 SDK 交给 App 的是十六进制串（DevUtil.decodeRaw），不是 base64。
    String hex(List<int> bytes) =>
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final day = <int>[
      ..._dayHeader,
      for (var i = 0; i < TuyaHistoryCodec.dailySamples; i++) i % 201,
    ];
    final lightWeek = <int>[
      26, 8, 14, 7, //
      0x23, 0x28, 0x00, 0x64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
    ];

    expect(
      TuyaHistoryCodec.decode(
        hex(day),
        range: ReportRange.day,
        sampleBytes: 1,
      ),
      TuyaHistoryCodec.decode(
        _payload(day),
        range: ReportRange.day,
        sampleBytes: 1,
      ),
    );
    expect(
      TuyaHistoryCodec.decode(
        hex(lightWeek),
        range: ReportRange.week,
        sampleBytes: 2,
      ),
      <double>[9000, 100, 0, 0, 0, 0, 1],
    );
  });

  group('164 / 165 的变长日帧按帧长判帧头', () {
    test('3 字节头：帧长是奇数，不可能是「4 字节头 + N×2」', () {
      final decoded = TuyaHistoryCodec.decode(
        _payload(<int>[26, 9, 16, 0x00, 0xf6, 0x01, 0x02, 0x00, 0xd2]),
        range: ReportRange.day,
        sampleBytes: 2,
        variableLength: true,
      );

      expect(decoded, <double>[246, 258, 210]);
    });

    test('4 字节头：帧长正好等于 4 + 点数 × 点宽', () {
      final decoded = TuyaHistoryCodec.decode(
        _payload(<int>[26, 9, 16, 3, 0x02, 0x29, 0x01, 0xf4, 0x02, 0x58]),
        range: ReportRange.day,
        sampleBytes: 2,
        variableLength: true,
      );

      expect(decoded, <double>[553, 500, 600]);
    });

    test('第 4 个字节对不上帧长时按 3 字节头解，不当点数', () {
      // 点数字节写 3 却只给了 2 个点：4 + 3×2 = 10 ≠ 8，退回 3 字节头。
      final decoded = TuyaHistoryCodec.decode(
        _payload(<int>[26, 9, 16, 3, 0x02, 0x29, 0x01, 0xf4]),
        range: ReportRange.day,
        sampleBytes: 2,
        variableLength: true,
      );

      // 8 字节按 3 字节头只解得出 2 个点，剩下的半个点丢掉。
      expect(decoded, <double>[0x0302, 0x2901]);
    });

    test('变长帧最多还是 96 个点', () {
      final decoded = TuyaHistoryCodec.decode(
        _payload(<int>[
          26,
          9,
          16,
          for (var i = 0; i < 200; i++) ...<int>[0, 1],
        ]),
        range: ReportRange.day,
        sampleBytes: 2,
        variableLength: true,
      );

      expect(decoded, hasLength(TuyaHistoryCodec.dailySamples));
    });
  });

  group('日包一次带 7 天（2026-09-17 固件）', () {
    // 09-11 → 09-17 七天，年偏移 26。
    List<int> perDayBlocks({
      int sampleBytes = 1,
      int days = 7,
      int firstDay = 11,
      bool countByte = false,
      int month = 9,
    }) => <int>[
      for (var day = 0; day < days; day++) ...<int>[
        26,
        month,
        firstDay + day,
        if (countByte) TuyaHistoryCodec.dailySamples,
        for (var i = 0; i < TuyaHistoryCodec.dailySamples; i++)
          ...(sampleBytes == 2
              ? <int>[0, (day * 10 + i) % 256]
              : <int>[(day * 10 + i) % 201]),
      ],
    ];

    test('每天一块带日期头：7 天各 96 点，按日期排到最新那天在最后', () {
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(perDayBlocks()),
        sampleBytes: 1,
      );

      expect(frames.layout, DailyHistoryLayout.perDayBlocks);
      expect(frames.days, hasLength(7));
      expect(frames.days.first.dayKey, '09-11');
      expect(frames.newest?.dayKey, '09-17');
      for (final slice in frames.days) {
        expect(slice.samples, hasLength(TuyaHistoryCodec.dailySamples));
        expect(slice.yearOffset, 26);
      }
      // 第 0 天第 0 点是 0，第 1 天第 0 点是 10：每天的数据没有串到别天去。
      expect(frames.days.first.samples.first, 0);
      expect(frames.days[1].samples.first, 10);
    });

    test('设备按新→旧排也认，翻成旧→新', () {
      final descending = <int>[
        for (var day = 6; day >= 0; day--) ...<int>[
          26,
          9,
          11 + day,
          for (var i = 0; i < TuyaHistoryCodec.dailySamples; i++) day,
        ],
      ];
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(descending),
        sampleBytes: 1,
      );

      expect(frames.layout, DailyHistoryLayout.perDayBlocks);
      expect(frames.days.first.dayKey, '09-11');
      expect(frames.newest?.dayKey, '09-17');
      // 翻过来之后点也要跟着走：最新那天原本是第一块（day == 6）。
      expect(frames.newest?.samples.first, 6);
    });

    test('跨月也连续：08-29 → 09-04', () {
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(<int>[
          for (final date in <List<int>>[
            <int>[8, 29],
            <int>[8, 30],
            <int>[8, 31],
            <int>[9, 1],
            <int>[9, 2],
            <int>[9, 3],
            <int>[9, 4],
          ])
            ...<int>[
              26,
              date[0],
              date[1],
              for (var i = 0; i < TuyaHistoryCodec.dailySamples; i++) 1,
            ],
        ]),
        sampleBytes: 1,
      );

      expect(frames.layout, DailyHistoryLayout.perDayBlocks);
      expect(frames.days, hasLength(7));
      expect(frames.newest?.dayKey, '09-04');
    });

    test('一个帧头 + 7 天点连排：帧头那天算起始日，往后逐日排', () {
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(<int>[
          26,
          9,
          11,
          for (var day = 0; day < 7; day++)
            for (var i = 0; i < TuyaHistoryCodec.dailySamples; i++)
              ...<int>[0, day],
        ]),
        sampleBytes: 2,
      );

      expect(frames.layout, DailyHistoryLayout.singleHeader);
      expect(frames.days, hasLength(7));
      expect(frames.days.first.dayKey, '09-11');
      expect(frames.newest?.dayKey, '09-17');
      expect(frames.newest?.samples.first, 6);
    });

    test('164 / 165 那种带点数字节的块头也认', () {
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(perDayBlocks(sampleBytes: 2, countByte: true)),
        sampleBytes: 2,
        variableLength: true,
      );

      expect(frames.layout, DailyHistoryLayout.perDayBlocks);
      expect(frames.days, hasLength(7));
      expect(frames.newest?.dayKey, '09-17');
      expect(
        frames.newest?.samples,
        hasLength(TuyaHistoryCodec.dailySamples),
      );
    });

    test('老固件只发一天照旧解得出来', () {
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(perDayBlocks(days: 1, firstDay: 17)),
        sampleBytes: 1,
      );

      // 单天帧就是 D == 1 的「每天一块」，同一套算式解出来。
      expect(frames.layout, DailyHistoryLayout.perDayBlocks);
      expect(frames.days, hasLength(1));
      expect(frames.days.single.dayKey, '09-17');
      expect(
        frames.days.single.samples,
        hasLength(TuyaHistoryCodec.dailySamples),
      );
    });

    test('日期头不合法时不认这种解法，退回按单天解', () {
      // 13 月：帧长对得上「7 天每天一块」，日期头对不上，说明认错了。
      final bytes = perDayBlocks(month: 13);
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(bytes),
        sampleBytes: 1,
      );

      expect(frames.layout, DailyHistoryLayout.legacySingleDay);
      expect(frames.days, hasLength(1));
    });

    test('日期不连续也不认：中间跳掉一天', () {
      final gapped = <int>[
        for (final day in <int>[11, 12, 14, 15, 16, 17, 18])
          ...<int>[
            26,
            9,
            day,
            for (var i = 0; i < TuyaHistoryCodec.dailySamples; i++) 1,
          ],
      ];
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(gapped),
        sampleBytes: 1,
      );

      expect(frames.layout, DailyHistoryLayout.legacySingleDay);
    });

    test('超过 7 天的窗口不认', () {
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(perDayBlocks(days: 8, firstDay: 10)),
        sampleBytes: 1,
      );

      expect(frames.layout, DailyHistoryLayout.legacySingleDay);
    });

    test('没有 payload 就是没有数据', () {
      for (final value in <Object?>[null, '', 'not base64!!']) {
        final frames = TuyaHistoryCodec.decodeDaily(value, sampleBytes: 1);
        expect(frames.layout, DailyHistoryLayout.none, reason: '$value');
        expect(frames.isEmpty, isTrue, reason: '$value');
      }
    });

    test('联调日志那行把认出来的帧写明白', () {
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(perDayBlocks()),
        sampleBytes: 1,
      );

      expect(frames.label, '7天×96点（每天一块带日期头）09-11→09-17');
    });

    test('按天分好之后：选哪天取哪天，最新那天给状态页', () {
      final frames = TuyaHistoryCodec.decodeDaily(
        _payload(perDayBlocks()),
        sampleBytes: 1,
      );
      // 仓库就是这么装进 DeviceHistory 的：series 放最新那天（状态页那条曲线照旧
      // 读它），_daily 放全部 7 天（报表按选中日期取）。
      final history = DeviceHistory(
        <String, List<double>>{
          DeviceHistory.key(SensorMetric.waterLevel, ReportRange.day):
              frames.newest!.samples,
        },
        <String, Map<String, List<double>>>{
          SensorMetric.waterLevel.name: <String, List<double>>{
            for (final slice in frames.days) slice.dayKey: slice.samples,
          },
        },
      );

      // 09-11 是第 0 天（首点 0），09-13 是第 2 天（首点 20）。
      expect(
        history.daySeries(SensorMetric.waterLevel, DateTime(2026, 9, 11)).first,
        0,
      );
      expect(
        history.daySeries(SensorMetric.waterLevel, DateTime(2026, 9, 13)).first,
        20,
      );
      // 窗口外的日期是空的，不拿别的一天顶上。
      expect(
        history.daySeries(SensorMetric.waterLevel, DateTime(2026, 9, 10)),
        isEmpty,
      );
      expect(history.reportedDays(SensorMetric.waterLevel), hasLength(7));
      // 没有日包的指标一天都没有。
      expect(history.reportedDays(SensorMetric.battery), isEmpty);
      // series 仍然是最新那天，状态页不受 7 天包影响。
      expect(
        history.series(SensorMetric.waterLevel, ReportRange.day).first,
        60,
      );
    });

    test('按天取数的键补零到 MM-DD', () {
      expect(DeviceHistory.dayKey(9, 7), '09-07');
      expect(DeviceHistory.dayKey(12, 31), '12-31');
      expect(DeviceHistory.dayKeyOf(DateTime(2026, 9, 17)), '09-17');
    });
  });

  test('a raw byte list decodes the same as its base64 form', () {
    final bytes = <int>[26, 8, 14, 7, 1, 2, 3, 4, 5, 6, 7];

    expect(
      TuyaHistoryCodec.decode(bytes, range: ReportRange.week, sampleBytes: 1),
      TuyaHistoryCodec.decode(
        _payload(bytes),
        range: ReportRange.week,
        sampleBytes: 1,
      ),
    );
  });
}
