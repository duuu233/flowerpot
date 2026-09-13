import 'dart:convert';

/// raw 功能点**上报值**的字节还原，历史报表（131–139）和纪念日（154/158/159）共用。
///
/// ⚠️ **SDK 交给 App 的是十六进制字符串，不是 base64。** 2026-09-13 解包涂鸦 Android
/// SDK 7.5.1（`thingsmart-device`）核对：设备上报 / 云端下来的 raw 值确实是 base64，
/// 但 SDK 在交给 `IDevListener.onDpUpdate` 和 `DeviceBean.getDps()` 之前会先过
/// `DevUtil.decodeRaw`——`Base64.decode` → `HexUtil.bytesToHexString`，也就是**转成
/// 十六进制串**；下发方向 `DevUtil.encodeRaw` 反过来 `hexStringToBytes` →
/// `encodeBase64`。所以两个方向在 App 这一侧都是十六进制，并不是「报 base64、写 hex」。
///
/// 之前按 base64 解：十六进制字符全都落在 base64 字母表里，不会报格式错，结果是
/// 长度不是 4 的倍数的包（日包 99 字节 → 198 个字符）直接解不出来、页面画「暂无
/// 历史数据」，长度凑巧是 4 的倍数的包则解出一串乱码。联调日志里「有数据」但报表
/// 没有，就是这个原因。
///
/// 仍然兼容 base64：iOS 桥接和测试夹具没有逐一核对过，按「先认十六进制、再认 base64」
/// 的顺序解。一段真正的 base64 恰好全是 `0-9a-f` 且长度为偶数的概率，对这些十几
/// 字节以上的包可以忽略。
abstract final class TuyaRaw {
  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

  /// 还原成字节；取不到或认不出时返回 null。
  static List<int>? bytes(Object? value) {
    if (value is List<int>) return value;
    if (value is! String) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    if (text.length.isEven && _hex.hasMatch(text)) {
      return <int>[
        for (var i = 0; i < text.length; i += 2)
          int.parse(text.substring(i, i + 2), radix: 16),
      ];
    }
    try {
      return base64.decode(text);
    } on FormatException {
      return null;
    }
  }

  /// 联调日志用：这条值是按哪种编码认出来的。
  static String encodingOf(Object? value) {
    if (value is List<int>) return '字节';
    if (value is! String || value.trim().isEmpty) return '空';
    final text = value.trim();
    if (text.length.isEven && _hex.hasMatch(text)) return 'hex';
    return bytes(text) == null ? '无法解码' : 'base64';
  }
}
