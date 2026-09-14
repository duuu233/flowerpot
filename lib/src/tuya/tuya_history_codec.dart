import 'tuya_models.dart';
import 'tuya_raw.dart';

/// Decoder for the nine raw history DPs (131–139).
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
/// The day packet has no count byte — it is always 96 quarter-hour samples.
/// Water level and soil moisture take one unsigned byte per sample; light takes
/// two, big endian.
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
  static List<double> decode(
    Object? value, {
    required ReportRange range,
    required int sampleBytes,
  }) {
    final bytes = TuyaRaw.bytes(value);
    if (bytes == null) return const <double>[];

    final headerBytes = range == ReportRange.day ? 3 : 4;
    if (bytes.length <= headerBytes) return const <double>[];

    final available = (bytes.length - headerBytes) ~/ sampleBytes;
    final declared = range == ReportRange.day ? dailySamples : bytes[3];
    final count = declared < available ? declared : available;
    if (count <= 0) return const <double>[];

    return <double>[
      for (var i = 0; i < count; i++)
        _sample(bytes, headerBytes + i * sampleBytes, sampleBytes),
    ];
  }

  static double _sample(List<int> bytes, int offset, int sampleBytes) {
    if (sampleBytes == 2) {
      return ((bytes[offset] << 8) | bytes[offset + 1]).toDouble();
    }
    return bytes[offset].toDouble();
  }
}
