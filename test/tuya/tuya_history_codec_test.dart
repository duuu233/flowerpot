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

  test('week and month packets take their length from the count byte', () {
    final week = TuyaHistoryCodec.decode(
      _payload(<int>[26, 8, 14, 7, 10, 20, 30, 40, 50, 60, 70]),
      range: ReportRange.week,
      sampleBytes: 1,
    );
    expect(week, <double>[10, 20, 30, 40, 50, 60, 70]);

    final month = TuyaHistoryCodec.decode(
      _payload(<int>[26, 8, 1, 3, 11, 12, 13]),
      range: ReportRange.month,
      sampleBytes: 1,
    );
    expect(month, <double>[11, 12, 13]);
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
