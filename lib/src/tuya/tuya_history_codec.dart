import 'tuya_models.dart';
import 'tuya_raw.dart';

/// 历史 DP 的帧解码：131–139，以及 164 / 165。
///
/// 帧格式以 `docs/app_DP_问题修正说明.md` §4 为准，**每一次 DP 上报就是一帧**：
///
/// ```text
/// 日（131/134/137/164/165）每天 1 帧，共 7 帧
///   [年偏移][月][日] + N × 点      N = (len − 3) ÷ 点宽；过去 6 天 N = 96，今天 N = 当前槽 + 1
/// 周（132/135/138）单帧
///   [年偏移][月][日][N] + N × 点   N ≤ 28，最后一个点 = 最近一次聚合日（通常是昨天）
/// 月（133/136/139）1~2 段
///   [年偏移][月][日][段号][总段数] + M × 点   M ≤ 90，段 0 = 最老，总点数 ≤ 180
/// ```
///
/// 年偏移 = 年份 − 2000。槽 k ⇔ 该帧日期 00:00 + k × 15 分钟。点宽：水位、土壤湿度
/// 1 字节；光照、空气温度、空气湿度 2 字节大端（空气温度**有符号**，支持负温）。
///
/// ⚠️ 设备是**分帧**发的：同一个 DP 一次全量上报会连发 7 个日帧（月是 1~2 段），而
/// 涂鸦的设备快照每个 DP 只留最后一个值。只解快照里那一帧，最后到的那帧（往往是 6 天
/// 前）就被当成了「今天」——这是「日历史对不上」的根因。跨推送把帧攒起来由
/// [HistoryFrameBuffer] 负责，本类只做**单帧**解码与帧长自检。
///
/// 帧长与帧头矛盾、日期不合法、未对时（见 [isUnsyncedDay]）的帧一律丢弃（返回 null），
/// 不尽力去猜——认错一帧就是一整条错位的曲线。
abstract final class TuyaHistoryCodec {
  /// 一天最多几个点，一刻钟一个。
  static const dailySamples = 96;

  /// 日帧帧头：年偏移 + 月 + 日。
  static const dayHeaderBytes = 3;

  /// 周帧帧头：年偏移 + 月 + 日 + 点数。
  static const weekHeaderBytes = 4;

  /// 周帧最多几个点（4 周的日均值）。
  static const weekMaxSamples = 28;

  /// 月帧帧头：年偏移 + 月 + 日 + 段号 + 总段数（没有点数字节）。
  static const monthHeaderBytes = 5;

  /// 月帧一段最多几个点。
  static const monthSegmentSamples = 90;

  /// 月帧最多几段：总点数 ≤ 180，每段 ≤ 90。
  static const monthMaxSegments = 2;

  /// 日历史一共几天：今天 + 往前 6 天。状态页 / 报表左右切日期的窗口也是这个数。
  static const maxDailyWindow = 7;

  /// 解一个日帧。帧长对不上、日期不合法或是未对时帧时返回 null（丢弃）。
  static HistoryDayFrame? decodeDayFrame(
    Object? value, {
    required int sampleBytes,
    bool signed = false,
  }) {
    final bytes = TuyaRaw.bytes(value);
    if (bytes == null || bytes.length < dayHeaderBytes + sampleBytes) {
      return null;
    }
    final body = bytes.length - dayHeaderBytes;
    if (body % sampleBytes != 0) return null;
    final count = body ~/ sampleBytes;
    // 帧长自检：日帧 ≤ 99B（1B 点）/ 195B（2B 点）。
    if (count > dailySamples) return null;
    final date = _date(bytes);
    if (date == null || isUnsyncedDay(date, count)) return null;
    return HistoryDayFrame(
      date: date,
      samples: _samples(bytes, dayHeaderBytes, count, sampleBytes, signed),
    );
  }

  /// 解一个周帧。N = 0（从未聚合，设备本不该发）、N > 28、帧长和 N 对不上时返回 null。
  static HistoryWindowFrame? decodeWeekFrame(
    Object? value, {
    required int sampleBytes,
    bool signed = false,
  }) {
    final bytes = TuyaRaw.bytes(value);
    if (bytes == null || bytes.length <= weekHeaderBytes) return null;
    final count = bytes[3];
    if (count < 1 || count > weekMaxSamples) return null;
    // 帧长自检：必须正好是 4 + N × 点宽（≤ 32B / 60B）。
    if (bytes.length != weekHeaderBytes + count * sampleBytes) return null;
    final date = _date(bytes);
    if (date == null) return null;
    return HistoryWindowFrame(
      date: date,
      samples: _samples(bytes, weekHeaderBytes, count, sampleBytes, signed),
    );
  }

  /// 解一个月段。段号 / 总段数不合法、帧长不是整点、单段超过 90 点时返回 null。
  static HistoryMonthSegment? decodeMonthSegment(
    Object? value, {
    required int sampleBytes,
    bool signed = false,
  }) {
    final bytes = TuyaRaw.bytes(value);
    if (bytes == null || bytes.length < monthHeaderBytes + sampleBytes) {
      return null;
    }
    final index = bytes[3];
    final total = bytes[4];
    if (total < 1 || total > monthMaxSegments || index >= total) return null;
    final body = bytes.length - monthHeaderBytes;
    if (body % sampleBytes != 0) return null;
    final count = body ~/ sampleBytes;
    // 帧长自检：≤ 95B / 185B。
    if (count > monthSegmentSamples) return null;
    final date = _date(bytes);
    if (date == null) return null;
    return HistoryMonthSegment(
      date: date,
      index: index,
      total: total,
      samples: _samples(bytes, monthHeaderBytes, count, sampleBytes, signed),
    );
  }

  /// 单帧解成点（联调日志、只看一帧时用）。解不出返回空列表。
  static List<double> decode(
    Object? value, {
    required ReportRange range,
    required int sampleBytes,
    bool signed = false,
  }) {
    final samples = switch (range) {
      ReportRange.day => decodeDayFrame(
        value,
        sampleBytes: sampleBytes,
        signed: signed,
      )?.samples,
      ReportRange.week => decodeWeekFrame(
        value,
        sampleBytes: sampleBytes,
        signed: signed,
      )?.samples,
      ReportRange.month => decodeMonthSegment(
        value,
        sampleBytes: sampleBytes,
        signed: signed,
      )?.samples,
    };
    return samples ?? const <double>[];
  }

  /// 未对时帧：设备还没拿到网络时间时帧头回退成 2026-01-01，**且**今天帧只有 1 个点。
  /// 两个条件同时满足才丢。
  static bool isUnsyncedDay(DateTime date, int count) =>
      count == 1 && date.year == 2026 && date.month == 1 && date.day == 1;

  static DateTime? _date(List<int> bytes) {
    final month = bytes[1];
    final day = bytes[2];
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(2000 + bytes[0], month, day);
    // 2 月 30 这种会被 DateTime 进位到下个月：进位了就是不合法的日期头。
    if (date.month != month || date.day != day) return null;
    return date;
  }

  static List<double> _samples(
    List<int> bytes,
    int offset,
    int count,
    int sampleBytes,
    bool signed,
  ) => <double>[
    for (var i = 0; i < count; i++)
      _sample(bytes, offset + i * sampleBytes, sampleBytes, signed),
  ];

  static double _sample(
    List<int> bytes,
    int offset,
    int sampleBytes,
    bool signed,
  ) {
    if (sampleBytes == 2) {
      final value = (bytes[offset] << 8) | bytes[offset + 1];
      return (signed && value >= 0x8000 ? value - 0x10000 : value).toDouble();
    }
    return bytes[offset].toDouble();
  }
}

/// 一个日帧：帧头日期 + 那天的点（今天那帧的点数随时间增长）。
class HistoryDayFrame {
  const HistoryDayFrame({required this.date, required this.samples});

  final DateTime date;
  final List<double> samples;

  /// `MM-DD`，与 [DeviceHistory.dayKey] 同一个格式。
  String get dayKey => DeviceHistory.dayKey(date.month, date.day);
}

/// 一个周帧：帧头日期 + 最老 → 最新的日均值。
class HistoryWindowFrame {
  const HistoryWindowFrame({required this.date, required this.samples});

  final DateTime date;
  final List<double> samples;
}

/// 月帧的一段。
class HistoryMonthSegment {
  const HistoryMonthSegment({
    required this.date,
    required this.index,
    required this.total,
    required this.samples,
  });

  final DateTime date;
  final int index;
  final int total;
  final List<double> samples;
}

/// 一台设备的历史帧缓冲：跨推送把分帧攒起来。
///
/// - 日：按**帧头日期**归档（不自行修正日期），同一天再来一帧就整块替换（今天那帧随
///   时间变长，跨 0 点后新一天从 1 个点开始）；只留最新那天往前
///   [TuyaHistoryCodec.maxDailyWindow] 天。
/// - 周：单帧，新帧直接替换。
/// - 月：按段号拼。帧头日期或总段数一变就是新的一期，旧段清掉重攒；没收齐时先用
///   已收到的段，不等第 2 段。
///
/// 同一帧重复喂进来是幂等的，所以每次拿到设备快照都可以把里面的历史 DP 再喂一次。
class HistoryFrameBuffer {
  final Map<String, Map<DateTime, List<double>>> _days =
      <String, Map<DateTime, List<double>>>{};
  final Map<String, HistoryWindowFrame> _weeks = <String, HistoryWindowFrame>{};
  final Map<String, _MonthSegments> _months = <String, _MonthSegments>{};

  void addDay(String identifier, HistoryDayFrame frame) {
    final days = _days.putIfAbsent(
      identifier,
      () => <DateTime, List<double>>{},
    );
    days[frame.date] = frame.samples;
    final newest = days.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    final oldest = DateTime(
      newest.year,
      newest.month,
      newest.day - (TuyaHistoryCodec.maxDailyWindow - 1),
    );
    days.removeWhere((date, _) => date.isBefore(oldest));
  }

  void addWeek(String identifier, HistoryWindowFrame frame) {
    _weeks[identifier] = frame;
  }

  void addMonth(String identifier, HistoryMonthSegment segment) {
    final current = _months[identifier];
    if (current == null ||
        current.total != segment.total ||
        current.date != segment.date) {
      _months[identifier] = _MonthSegments(segment.date, segment.total)
        ..segments[segment.index] = segment.samples;
      return;
    }
    current.segments[segment.index] = segment.samples;
  }

  /// 日帧，按日期从旧到新。
  List<HistoryDayFrame> days(String identifier) {
    final days = _days[identifier];
    if (days == null || days.isEmpty) return const <HistoryDayFrame>[];
    final dates = days.keys.toList()..sort();
    return <HistoryDayFrame>[
      for (final date in dates)
        HistoryDayFrame(date: date, samples: days[date]!),
    ];
  }

  List<double> week(String identifier) =>
      _weeks[identifier]?.samples ?? const <double>[];

  /// 月曲线：已收到的段按段号从老到新拼起来。
  List<double> month(String identifier) {
    final month = _months[identifier];
    if (month == null) return const <double>[];
    final indexes = month.segments.keys.toList()..sort();
    return <double>[for (final index in indexes) ...month.segments[index]!];
  }

  /// 月帧收齐了没有（每一段都到了）。
  bool monthComplete(String identifier) {
    final month = _months[identifier];
    return month != null && month.segments.length == month.total;
  }
}

class _MonthSegments {
  _MonthSegments(this.date, this.total);

  final DateTime date;
  final int total;
  final Map<int, List<double>> segments = <int, List<double>>{};
}
