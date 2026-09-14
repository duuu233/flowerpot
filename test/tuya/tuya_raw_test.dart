import 'dart:convert';

import 'package:flowerpot/src/tuya/tuya_raw.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('the SDK hands raw DPs over as hex, either case', () {
    final bytes = <int>[26, 9, 13, 0x00, 0xC8, 0xFF];

    // 涂鸦 SDK 的 DevUtil.decodeRaw 交上来的就是这种小写十六进制串。
    expect(TuyaRaw.bytes(_hex(bytes)), bytes);
    expect(TuyaRaw.bytes(_hex(bytes).toUpperCase()), bytes);
    expect(TuyaRaw.encodingOf(_hex(bytes)), 'hex');
  });

  test('base64 still decodes', () {
    final bytes = <int>[26, 8, 14, 7, 10, 20, 30, 40, 50, 60, 70];

    expect(TuyaRaw.bytes(base64.encode(bytes)), bytes);
    expect(TuyaRaw.encodingOf(base64.encode(bytes)), 'base64');
  });

  test('a day packet as hex is not mistaken for base64', () {
    // 3 字节表头 + 96 个点 = 99 字节 → 198 个十六进制字符。按 base64 解时长度
    // 不是 4 的倍数直接失败，报表就只剩「暂无历史数据」。
    final bytes = <int>[26, 9, 13, for (var i = 0; i < 96; i++) i % 201];
    final hex = _hex(bytes);

    expect(hex.length, 198);
    expect(TuyaRaw.bytes(hex), bytes);
  });

  test('nothing usable reads as null', () {
    for (final value in <Object?>[null, '', '   ', 'not base64!!', 42]) {
      expect(TuyaRaw.bytes(value), isNull, reason: 'value: $value');
    }
    expect(TuyaRaw.bytes(<int>[1, 2]), <int>[1, 2]);
  });
}
