import 'dart:convert';

import 'package:flowerpot/src/tuya/tuya_memorial_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a custom entry round-trips through the 154 frame', () {
    final frame = TuyaMemorialCodec.encodeEntry(
      id: 0x01020304,
      date: DateTime(2026, 8, 31),
      type: MemorialContentType.text,
      content: '认识100天',
    );

    // | ID(4B) | 日期(4B) | type(1B) | 长度(1B) | 内容 |
    expect(frame.sublist(0, 4), <int>[0x01, 0x02, 0x03, 0x04]);
    expect(frame.sublist(4, 8), <int>[
      (20260831 >> 24) & 0xFF,
      (20260831 >> 16) & 0xFF,
      (20260831 >> 8) & 0xFF,
      20260831 & 0xFF,
    ]);
    expect(frame[8], 1);
    expect(frame[9], utf8.encode('认识100天').length);

    final decoded = TuyaMemorialCodec.decodeEntry(frame)!;
    expect(decoded.id, 0x01020304);
    expect(decoded.date, DateTime(2026, 8, 31));
    expect(decoded.type, MemorialContentType.text);
    expect(decoded.content, '认识100天');
    expect(decoded.enabled, isTrue);
    expect(decoded.dateLabel, '2026-08-31');
  });

  test('disable keeps the entry, delete removes it', () {
    final disabled = TuyaMemorialCodec.encodeEntry(
      id: 7,
      date: DateTime(2026, 8, 31),
      type: MemorialContentType.image,
      content: 'https://example.com/a.png',
      enabled: false,
    );
    // 停用帧的日期是 0，type 和内容都不带——设备按 id 认这条数据还在。
    expect(disabled.sublist(4, 8), <int>[0, 0, 0, 0]);
    expect(disabled[8], 0);
    expect(disabled[9], 0);
    expect(TuyaMemorialCodec.decodeEntry(disabled)?.enabled, isFalse);
    expect(TuyaMemorialCodec.decodeEntry(disabled)?.date, isNull);

    final deleted = TuyaMemorialCodec.encodeDelete(7);
    expect(
      deleted.sublist(4, 8),
      <int>[
        (111111 >> 24) & 0xFF,
        (111111 >> 16) & 0xFF,
        (111111 >> 8) & 0xFF,
        111111 & 0xFF,
      ],
    );
  });

  test('the fixed dates are eight ASCII bytes', () {
    expect(
      ascii.decode(TuyaMemorialCodec.encodeFixedDate(DateTime(2026, 8, 29))),
      '20260829',
    );
    expect(
      ascii.decode(TuyaMemorialCodec.encodeFixedDate(null)),
      TuyaMemorialCodec.disabledAsciiDate,
    );
    expect(
      ascii.decode(TuyaMemorialCodec.encodeFixedDelete()),
      TuyaMemorialCodec.deletedAsciiDate,
    );
    expect(
      TuyaMemorialCodec.decodeFixedDate(ascii.encode('20260829')),
      DateTime(2026, 8, 29),
    );
    // 两个哨兵值都不是日期。
    expect(TuyaMemorialCodec.decodeFixedDate(ascii.encode('00000000')), isNull);
    expect(TuyaMemorialCodec.decodeFixedDate(ascii.encode('11111111')), isNull);
  });

  test('a corrupt payload reads as "nothing set" instead of throwing', () {
    expect(TuyaMemorialCodec.decodeEntry(null), isNull);
    expect(TuyaMemorialCodec.decodeEntry('not base64!!'), isNull);
    expect(TuyaMemorialCodec.decodeEntry(<int>[1, 2, 3]), isNull);
    expect(TuyaMemorialCodec.decodeFixedDate(<int>[1, 2]), isNull);
    // 2026-02-31 不存在，DateTime 会滚到三月，那是坏包不是用户选的日期。
    expect(TuyaMemorialCodec.dateFromValue(20260231), isNull);
    expect(TuyaMemorialCodec.dateFromValue(20261301), isNull);
  });

  test('raw writes go out as hex', () {
    expect(TuyaMemorialCodec.encodeRaw(<int>[0x00, 0x0A, 0xFF]), '000AFF');
  });

  test('reports arrive base64 encoded', () {
    final frame = TuyaMemorialCodec.encodeEntry(
      id: 9,
      date: DateTime(2026, 1, 2),
      type: MemorialContentType.text,
      content: '生日快乐',
    );
    final decoded = TuyaMemorialCodec.decodeEntry(base64.encode(frame))!;
    expect(decoded.id, 9);
    expect(decoded.content, '生日快乐');
    expect(decoded.date, DateTime(2026, 1, 2));
  });
}
