import 'dart:convert';
import 'dart:typed_data';

import 'tuya_repository.dart' show TuyaException;

/// 定制动画（设备图库）相关 raw 功能点的帧格式。
///
/// 依据 `docs/智能花盆test(yciq4kssu1fv8umn)_09_12.xlsx` 功能点表：
///
/// | DP | 标识符 | 类型 | 格式 |
/// | --- | --- | --- | --- |
/// | 142 | `dl_url` 下载图片 | raw，只下发 | `url_len(1B) + url + name_len(1B) + name` |
/// | 155 | `del_photo` 删除指定照片 | raw，只下发 | 照片文件名 ASCII |
/// | 157 | `pin_photo` 置顶照片 | raw，只下发 | 照片文件名 ASCII |
///
/// ⚠️ **142 里的 name 必须和 155 / 157 发的是同一个文件名**，设备按它存、按它删、按它置顶。
/// App 这边三处统一用 `BackendImage.fileNameOf` 从图片 URL 取最后一段。
abstract final class TuyaGalleryCodec {
  /// 长度字段只有 1 字节。
  static const int maxFieldBytes = 255;

  /// DP 142 `dl_url` 的帧：`url_len(1B) + url + name_len(1B) + name`。
  ///
  /// URL 按 UTF-8 取字节；文件名要求 ASCII（155 / 157 的格式就是「文件名 ASCII」，
  /// 这里不是 ASCII 的话后面删不掉、置顶不了）。任一段超过 255 字节或为空都直接报错，
  /// 不截断——截断的 URL 设备下不到，截断的文件名删不掉。
  static Uint8List downloadFrame({required String url, required String name}) {
    final urlBytes = utf8.encode(url.trim());
    if (urlBytes.isEmpty) {
      throw const TuyaException('dl_url_empty', '图片地址为空，无法通知设备下载');
    }
    if (urlBytes.length > maxFieldBytes) {
      throw TuyaException(
        'dl_url_too_long',
        '图片地址 ${urlBytes.length} 字节，超过设备协议的 $maxFieldBytes 字节上限',
      );
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const TuyaException('dl_name_empty', '图片文件名为空，无法通知设备下载');
    }
    if (trimmedName.codeUnits.any((unit) => unit > 0x7F)) {
      throw TuyaException(
        'dl_name_not_ascii',
        '图片文件名「$trimmedName」含非 ASCII 字符，设备协议只收 ASCII 文件名',
      );
    }
    final nameBytes = ascii.encode(trimmedName);
    if (nameBytes.length > maxFieldBytes) {
      throw TuyaException(
        'dl_name_too_long',
        '图片文件名 ${nameBytes.length} 字节，超过设备协议的 $maxFieldBytes 字节上限',
      );
    }
    return (BytesBuilder()
          ..addByte(urlBytes.length)
          ..add(urlBytes)
          ..addByte(nameBytes.length)
          ..add(nameBytes))
        .toBytes();
  }
}
