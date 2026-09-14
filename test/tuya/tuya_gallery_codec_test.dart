import 'dart:convert';

import 'package:flowerpot/src/core/backend/backend.dart';
import 'package:flowerpot/src/tuya/tuya_gallery_codec.dart';
import 'package:flowerpot/src/tuya/tuya_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DP 142 dl_url 帧：url_len(1B) + url + name_len(1B) + name', () {
    const url = 'https://cdn.example.test/a/b.gif';
    final frame = TuyaGalleryCodec.downloadFrame(url: url, name: 'b.gif');

    expect(frame[0], url.length);
    expect(ascii.decode(frame.sublist(1, 1 + url.length)), url);
    expect(frame[1 + url.length], 5);
    expect(ascii.decode(frame.sublist(2 + url.length)), 'b.gif');
    expect(frame.length, 1 + url.length + 1 + 5);
  });

  test('超过 1 字节长度上限、文件名非 ASCII、为空都直接报错，不截断', () {
    final longUrl = 'https://cdn.example.test/${'a' * 240}.gif';
    expect(
      () => TuyaGalleryCodec.downloadFrame(url: longUrl, name: 'a.gif'),
      throwsA(
        isA<TuyaException>().having((e) => e.code, 'code', 'dl_url_too_long'),
      ),
    );
    expect(
      () => TuyaGalleryCodec.downloadFrame(
        url: 'https://cdn.example.test/图.gif',
        name: '图.gif',
      ),
      throwsA(
        isA<TuyaException>().having(
          (e) => e.code,
          'code',
          'dl_name_not_ascii',
        ),
      ),
    );
    expect(
      () => TuyaGalleryCodec.downloadFrame(url: 'https://x.test/', name: ''),
      throwsA(
        isA<TuyaException>().having((e) => e.code, 'code', 'dl_name_empty'),
      ),
    );
  });

  test('设备上的文件名取 URL 最后一段：142 下发与 155 删除 / 157 置顶同一个名字', () {
    expect(
      BackendImage.fileNameOf('https://cdn.example.test/upload/2026/09/x1.jpg'),
      'x1.jpg',
    );
    expect(
      BackendImage.fileNameOf('https://cdn.example.test/p/a%20b.png?v=1'),
      'a b.png',
    );
    expect(BackendImage.fileNameOf(''), '');
  });
}
