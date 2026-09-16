import 'tuya_models.dart';
import 'tuya_raw.dart';

/// Decoder for the raw history DPs: 131–139, plus 164 / 165 since the 09-16
/// export.
///
/// The device pushes one packet per metric and window. Layouts, from the
/// platform export:
///
/// ```text
/// byte      0        1     2         3          4..
/// day     年偏移     月     日      ── 96 samples ──
/// week    年偏移     月   起始日   点数(7)    samples
/// month   年偏移     月   起始日   点数(31)   samples
/// ```
///
/// The 131–139 day packet has no count byte — it is always 96 quarter-hour
/// samples. Water level and soil moisture take one unsigned byte per sample;
/// light, air temperature and air humidity take two, big endian.
///
/// 164（空气温度日历史）和 165（空气湿度日历史）是**变长**日帧，而且 09-16 那版
/// 导出把两行写成了不同的帧头：164 是「年 月 日 + N×点数据」（3 字节头），165 是
/// 「年 月 日 N + N×点数据」（4 字节头）。同为日历史却不一样，且 165 那格的说明
/// 整段是周 / 月的口径，像是抄串了。认错帧头会让整条曲线错位一个字节，所以这两条
/// 走 [variableLength]：**按帧长判**，4 字节头成立当且仅当
/// `len == 4 + 点数 × 点宽`，否则按 3 字节头。点宽为 2 时 `3 + 2N` 恒为奇数、
/// `4 + 2k` 恒为偶数，两种解释的帧长不可能相等，所以这个判定是精确的，不是猜。
///
/// The leading date bytes are skipped: the charts plot a bare series today.
/// Read them here if a screen ever needs to label which day a packet covers,
/// or to spot a device replaying a stale window.
abstract final class TuyaHistoryCodec {
  /// Samples in a day packet, one per quarter hour.
  static const dailySamples = 96;

  /// Decodes one raw DP payload, or returns an empty list when the payload is
  /// missing, unreadable or shorter than its own header claims.
  ///
  /// A malformed packet reads as "no history yet" rather than throwing: the
  /// charts already handle an empty series, and a device mid-firmware-update
  /// should not take a status page down.
  ///
  /// [variableLength] 是 164 / 165 那种变长日帧：帧头是 3 还是 4 字节按帧长现算，
  /// 见类文档。131–139 一律不传，帧头按 [range] 定死。
  static List<double> decode(
    Object? value, {
    required ReportRange range,
    required int sampleBytes,
    bool variableLength = false,
  }) {
    final bytes = TuyaRaw.bytes(value);
    if (bytes == null) return const <double>[];

    final counted = variableLength
        ? _hasCountByte(bytes, sampleBytes)
        : range != ReportRange.day;
    final headerBytes = counted ? 4 : 3;
    if (bytes.length <= headerBytes) return const <double>[];

    final available = (bytes.length - headerBytes) ~/ sampleBytes;
    final declared = counted ? bytes[3] : dailySamples;
    final count = declared < available ? declared : available;
    if (count <= 0) return const <double>[];

    return <double>[
      for (var i = 0; i < count; i++)
        _sample(bytes, headerBytes + i * sampleBytes, sampleBytes),
    ];
  }

  /// 变长帧的第 4 个字节是不是点数：只有帧长正好等于 `4 + 点数 × 点宽` 时才算。
  static bool _hasCountByte(List<int> bytes, int sampleBytes) =>
      bytes.length >= 4 && bytes.length == 4 + bytes[3] * sampleBytes;

  static double _sample(List<int> bytes, int offset, int sampleBytes) {
    if (sampleBytes == 2) {
      return ((bytes[offset] << 8) | bytes[offset + 1]).toDouble();
    }
    return bytes[offset].toDouble();
  }
}
