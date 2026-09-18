import 'tuya_models.dart';
import 'tuya_raw.dart';

/// Decoder for the raw history DPs: 131–139, plus 164 / 165 since the 09-16
/// export.
///
/// The device pushes one packet per metric and window. Layouts, from the
/// platform export:
///
/// ```text
/// byte      0        1     2       3        4        5..
/// day     年偏移     月     日    ──── 96 点（今天那帧变长）────
/// week    年偏移     月     日   点数N(≤28)  ──── N 点 ────
/// month   年偏移     月     日    段号    总段数   ── 本段点 ──
/// ```
///
/// The 131–139 day packet has no count byte — it is always 96 quarter-hour
/// samples. Water level and soil moisture take one unsigned byte per sample;
/// light, air temperature and air humidity take two, big endian.
///
/// ⚠️ **月帧 2026-09-18 起是 5 字节头**（设备端 1.0.13 更新说明 §2.4）：第 4、5 字节
/// 是**段号**与**总段数**，**没有点数字节**，点数由帧长推（`(len − 5) ÷ 点宽`）。
/// 一整期最多 180 天、每段 90 点，所以满数据时是**两帧**（段 0 = 第 0~89 天、
/// 段 1 = 第 90~179 天），N < 90 时只有段 0。
///
/// 按旧口径（4 字节头 + 点数字节）解 1.0.13 的月帧会把**段号当成点数**：
/// 段 0 的那一帧 `bytes[3] == 0` ⇒ 解出 0 个点、月曲线整条空白；段 1 ⇒ 只剩 1 个点。
/// 这是个不报错的错解，只有真机上「月视图没数据」看得出来。
///
/// 周帧的点数字节仍在，但含义是**环内有效天数 ≤ 28**（4 周的日均值），
/// 不是早期导出写的「7」。取值从字节里读，这个变化不影响解码。
///
/// 164（空气温度日历史）和 165（空气湿度日历史）是**变长**日帧，而且 09-16 那版
/// 导出把两行写成了不同的帧头：164 是「年 月 日 + N×点数据」（3 字节头），165 是
/// 「年 月 日 N + N×点数据」（4 字节头）。同为日历史却不一样，且 165 那格的说明
/// 整段是周 / 月的口径，像是抄串了。固件 1.0.12 把 165 做成与 164 对称（点宽也统一
/// 成 2 字节大端 ×10），按对称口径它就是 3 字节头，但导出那一行没改，设备上的固件
/// 版本也不由 App 说了算。认错帧头会让整条曲线错位一个字节，所以这两条一直走
/// [variableLength]：**按帧长判**，4 字节头成立当且仅当
/// `len == 4 + 点数 × 点宽`，否则按 3 字节头。点宽为 2 时 `3 + 2N` 恒为奇数、
/// `4 + 2k` 恒为偶数，两种解释的帧长不可能相等，所以这个判定是精确的，不是猜。
///
/// The leading date bytes are skipped: the charts plot a bare series today.
/// Read them here if a screen ever needs to label which day a packet covers,
/// or to spot a device replaying a stale window.
abstract final class TuyaHistoryCodec {
  /// Samples in a day packet, one per quarter hour.
  static const dailySamples = 96;

  /// 月帧的帧头长度：年偏移 + 月 + 日 + 段号 + 总段数（设备端 1.0.13 §2.4）。
  static const monthHeaderBytes = 5;

  /// 月帧一段最多几个点（设备端 1.0.13：总点数 ≤180，每段 90）。
  static const monthSegmentSamples = 90;

  /// 取月帧的**段号与总段数**，不是月帧（或读不出来）返回 null。
  ///
  /// 一整期满数据时设备分两帧发（段 0 = 第 0~89 天、段 1 = 第 90~179 天），
  /// 两帧走的是**同一个 DP**。涂鸦交上来的设备状态只保留每个 DP 的最后一个值，
  /// 所以 App 这边拿到的通常只有**后到的那一段**。
  ///
  /// ⚠️ 要画满半年就得把两段按段号拼起来，而拼接需要跨推送把两帧都留住 ——
  /// 那是状态层的事（`DeviceHistory` 现在是「一个 (指标, 周期) 一条序列」），
  /// 本方法先把段信息暴露出来，接的时候不用再回来改解码。
  static (int index, int total)? monthSegment(Object? value) {
    final bytes = TuyaRaw.bytes(value);
    if (bytes == null || bytes.length <= monthHeaderBytes) return null;
    final index = bytes[3];
    final total = bytes[4];
    // 段号必须落在总段数里，总段数至少 1；不满足就不是段帧（可能是旧固件的月帧）。
    if (total < 1 || index >= total) return null;
    return (index, total);
  }

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

    // 三种帧头，按 range 定（164 / 165 那两条变长日帧另按帧长判，见 [_hasCountByte]）：
    //   日 3 字节、周 4 字节（末位是点数）、**月 5 字节（段号 + 总段数，没有点数）**。
    final int headerBytes;
    // 帧里**声明**的点数；月帧没有这个字节，用 null 表示「点数看帧长」。
    final int? declared;
    if (range == ReportRange.month && !variableLength) {
      headerBytes = monthHeaderBytes;
      declared = null;
    } else if (variableLength
        ? _hasCountByte(bytes, sampleBytes)
        : range != ReportRange.day) {
      headerBytes = 4;
      declared = bytes.length > 3 ? bytes[3] : 0;
    } else {
      headerBytes = 3;
      declared = dailySamples;
    }
    if (bytes.length <= headerBytes) return const <double>[];

    final available = (bytes.length - headerBytes) ~/ sampleBytes;
    // 声明的点数只用来**截短**，不用来补长：帧被截断时按实际有的解，别读过界。
    final count = declared == null || declared > available ? available : declared;
    if (count <= 0) return const <double>[];

    return <double>[
      for (var i = 0; i < count; i++)
        _sample(bytes, headerBytes + i * sampleBytes, sampleBytes),
    ];
  }

  /// 变长帧的第 4 个字节是不是点数：只有帧长正好等于 `4 + 点数 × 点宽` 时才算。
  static bool _hasCountByte(List<int> bytes, int sampleBytes) =>
      bytes.length >= 4 && bytes.length == 4 + bytes[3] * sampleBytes;

  /// 日包最多带几天：**当天 + 往前 6 天**（2026-09-17 固件改成一次上报 7 天）。
  /// 报表左右切日期的窗口也是这一个数。
  static const maxDailyWindow = 7;

  /// 把一条**日包** DP 解成按天分好的数据。
  ///
  /// 固件 2026-09-17 起一次上报 7 天，而功能点表还没导出新帧格式，所以这里
  /// **按帧长认**，依次试三种：
  ///
  /// ```text
  /// A 每天一块  [年偏移 月 日 (点数) + N点] × D   len == D × (头 + N×点宽)
  /// B 一个帧头  [年偏移 月 日] + 96点 × D         len == 3 + 96×D×点宽
  /// C 旧单天    [年偏移 月 日 + 96点]              兜底，长度对不齐也尽力解
  /// ```
  ///
  /// A 和 B 的帧长撞不上：点宽 1 时 A 是 99D（99 / 198 / … / 693），B 是 675；
  /// 点宽 2 时 A 是 195D（195 / … / 1365），B 是 1347。都不在对方的取值里。
  ///
  /// 认出长度之后还要过日期头这道校验：月 1–12、日 1–31，多天之间**逐日连续**
  /// （升序降序都行，降序翻成升序返回）。光看长度不够——一段点数据凑巧凑出合法
  /// 帧长的概率不低，日期头才是能把它挡住的那一关。
  ///
  /// 真机上核对看联调日志里 [DailyHistoryFrames.label] 那一段：认的是哪种帧、几天、
  /// 每天几点、覆盖哪几天，都在那一行里。
  static DailyHistoryFrames decodeDaily(
    Object? value, {
    required int sampleBytes,
    bool variableLength = false,
  }) {
    final bytes = TuyaRaw.bytes(value);
    if (bytes == null || bytes.isEmpty) return DailyHistoryFrames.empty;

    // 变长帧（164 / 165）的块头可能带点数字节，3 和 4 两种头都试；131–139 的日帧
    // 只有 3 字节头。
    final headers = variableLength ? const <int>[3, 4] : const <int>[3];
    for (final headerBytes in headers) {
      final days = _perDayBlocks(
        bytes,
        headerBytes: headerBytes,
        sampleBytes: sampleBytes,
      );
      if (days != null) {
        return DailyHistoryFrames(DailyHistoryLayout.perDayBlocks, days);
      }
    }
    final concatenated = _singleHeaderDays(bytes, sampleBytes: sampleBytes);
    if (concatenated != null) {
      return DailyHistoryFrames(DailyHistoryLayout.singleHeader, concatenated);
    }
    // 兜底：长度对不上任何一种（固件又改了、或者包被截断），按老单天帧解一条出来，
    // 总比整页空着好。
    final samples = decode(
      value,
      range: ReportRange.day,
      sampleBytes: sampleBytes,
      variableLength: variableLength,
    );
    if (samples.isEmpty) return DailyHistoryFrames.empty;
    return DailyHistoryFrames(
      DailyHistoryLayout.legacySingleDay,
      <DailyHistorySlice>[
        DailyHistorySlice(
          yearOffset: bytes[0],
          month: bytes[1],
          day: bytes[2],
          samples: samples,
        ),
      ],
    );
  }

  /// A：每天一个独立块。返回 null 表示这种解法不成立，换下一种。
  static List<DailyHistorySlice>? _perDayBlocks(
    List<int> bytes, {
    required int headerBytes,
    required int sampleBytes,
  }) {
    if (bytes.length < headerBytes + sampleBytes) return null;
    // 3 字节头的块内点数定死 96（09_12 功能点表的日帧）；4 字节头的点数写在第 4 个
    // 字节里，按第一块的值算——D 个块必须一样长，否则块边界无从算起，所以下面每
    // 块再核一次那个字节。
    final points = headerBytes == 4 ? bytes[3] : dailySamples;
    if (points <= 0) return null;
    final blockLength = headerBytes + points * sampleBytes;
    if (bytes.length % blockLength != 0) return null;
    final dayCount = bytes.length ~/ blockLength;
    if (dayCount < 1 || dayCount > maxDailyWindow) return null;
    final days = <DailyHistorySlice>[];
    for (var index = 0; index < dayCount; index++) {
      final offset = index * blockLength;
      final month = bytes[offset + 1];
      final day = bytes[offset + 2];
      if (!_isPlausibleDate(month, day)) return null;
      if (headerBytes == 4 && bytes[offset + 3] != points) return null;
      days.add(
        DailyHistorySlice(
          yearOffset: bytes[offset],
          month: month,
          day: day,
          samples: <double>[
            for (var point = 0; point < points; point++)
              _sample(
                bytes,
                offset + headerBytes + point * sampleBytes,
                sampleBytes,
              ),
          ],
        ),
      );
    }
    return _ascending(days);
  }

  /// B：一个帧头 + 多天的点连排。帧头那个日期按**起始日**算（和周 / 月包的
  /// 「起始日」同一个口径），后面的日期逐日往后推。
  ///
  /// 只认 3 字节头：4 字节头那个点数字节最大 255，装不下 7 × 96 = 672 个点，这种
  /// 组合不存在。D == 1 归 A 管（那就是老单天帧），所以这里从 2 天起。
  static List<DailyHistorySlice>? _singleHeaderDays(
    List<int> bytes, {
    required int sampleBytes,
  }) {
    const headerBytes = 3;
    final dayLength = dailySamples * sampleBytes;
    if (bytes.length <= headerBytes) return null;
    if ((bytes.length - headerBytes) % dayLength != 0) return null;
    final dayCount = (bytes.length - headerBytes) ~/ dayLength;
    if (dayCount < 2 || dayCount > maxDailyWindow) return null;
    if (!_isPlausibleDate(bytes[1], bytes[2])) return null;
    // 往后推第 index 天：交给 `DateTime` 的构造函数进位（`day + index` 越界会自动
    // 跨月）。年份取 2000 + 年偏移，涂鸦「年偏移」的惯例基准——它只影响 2 月末怎么
    // 进位，匹配用的键是 (月, 日)，不是年。
    final start = DateTime(2000 + bytes[0], bytes[1], bytes[2]);
    final days = <DailyHistorySlice>[];
    for (var index = 0; index < dayCount; index++) {
      final date = DateTime(start.year, start.month, start.day + index);
      final offset = headerBytes + index * dayLength;
      days.add(
        DailyHistorySlice(
          yearOffset: bytes[0],
          month: date.month,
          day: date.day,
          samples: <double>[
            for (var point = 0; point < dailySamples; point++)
              _sample(bytes, offset + point * sampleBytes, sampleBytes),
          ],
        ),
      );
    }
    return days;
  }

  /// 日期头像不像个日期。只查月 1–12、日 1–31，**不查每月实际天数**：没有可信的
  /// 年份，2 月 29 也可能是对的。这一关的用处是把「点数据被当成日期头」挡掉。
  static bool _isPlausibleDate(int month, int day) =>
      month >= 1 && month <= 12 && day >= 1 && day <= 31;

  /// 多天必须**逐日连续**，升序降序都算；降序翻成升序返回，好让调用方一律按
  /// 「最后一个是最新那天」用。不连续返回 null——那说明这种解法认错了。
  static List<DailyHistorySlice>? _ascending(List<DailyHistorySlice> days) {
    if (days.length == 1) return days;
    if (_isConsecutive(days)) return days;
    final reversed = days.reversed.toList(growable: false);
    if (_isConsecutive(reversed)) return reversed;
    return null;
  }

  /// 相邻两天是不是「后一天正好是前一天的第二天」。没有年份，所以跨月只按「下个
  /// 月 1 号」算：不查上个月有几天，28 / 29 / 30 / 31 号接 1 号都认。
  static bool _isConsecutive(List<DailyHistorySlice> days) {
    for (var index = 1; index < days.length; index++) {
      final previous = days[index - 1];
      final current = days[index];
      final sameMonth =
          current.month == previous.month && current.day == previous.day + 1;
      final nextMonth =
          current.day == 1 &&
          previous.day >= 28 &&
          current.month == previous.month % 12 + 1;
      if (!sameMonth && !nextMonth) return false;
    }
    return true;
  }

  static double _sample(List<int> bytes, int offset, int sampleBytes) {
    if (sampleBytes == 2) {
      return ((bytes[offset] << 8) | bytes[offset + 1]).toDouble();
    }
    return bytes[offset].toDouble();
  }
}

/// 一天的日历史：帧里那三个日期字节 + 那天的点。
///
/// **不带年**：日期头第一个字节是「年偏移」，功能点表没写基准年（2000 还是别的），
/// 而 App 需要的只是「这一天是不是我选中的那一天」——7 天窗口里 (月, 日) 不会
/// 重复，所以匹配按 `MM-DD` 走，年偏移只留着打进联调日志。
class DailyHistorySlice {
  const DailyHistorySlice({
    required this.yearOffset,
    required this.month,
    required this.day,
    required this.samples,
  });

  final int yearOffset;
  final int month;
  final int day;
  final List<double> samples;

  /// `MM-DD`，与 [DeviceHistory.dayKey] 同一个格式。
  String get dayKey => DeviceHistory.dayKey(month, day);
}

/// 日包认出来的是哪一种帧。联调日志里要打明文——两种帧解错一个，整条曲线就是
/// 错位的垃圾数据，真机上得能一眼看出 App 认的是哪种。
enum DailyHistoryLayout {
  /// 每天一个独立块，块头带日期：`[年偏移 月 日 (点数) + N 点] × D`。
  perDayBlocks('每天一块带日期头'),

  /// 一个帧头 + 多天的点连排：`[年偏移 月 日] + 96 点 × D`，帧头标的是**起始日**
  /// （和周 / 月包的「起始日」同一个口径），后面逐日往后排。
  singleHeader('一个帧头+多天点连排'),

  /// 长度对不上前两种时的兜底：按 09_12 功能点表那个单天帧尽力解一条曲线出来。
  legacySingleDay('旧单天帧'),

  /// 一个点都没解出来。
  none('解不出');

  const DailyHistoryLayout(this.label);

  final String label;
}

/// 一条日包 DP 解出来的全部天数。
class DailyHistoryFrames {
  const DailyHistoryFrames(this.layout, this.days);

  static const empty = DailyHistoryFrames(
    DailyHistoryLayout.none,
    <DailyHistorySlice>[],
  );

  final DailyHistoryLayout layout;

  /// 按日期**从旧到新**排好；设备按哪个方向排都在 [TuyaHistoryCodec] 里归一化过。
  final List<DailyHistorySlice> days;

  bool get isEmpty => days.isEmpty;

  /// 最新那一天。状态页和首页那条曲线要的就是这天（以前日包只有一天，就是它）。
  DailyHistorySlice? get newest => days.isEmpty ? null : days.last;

  /// 联调日志里那一行：`7天×96点（每天一块带日期头）09-11→09-17`。
  String get label {
    if (days.isEmpty) return layout.label;
    final points = days.map((item) => item.samples.length).toSet();
    final width = points.length == 1 ? '${points.single}点' : '点数不齐$points';
    final span = days.length == 1
        ? days.single.dayKey
        : '${days.first.dayKey}→${days.last.dayKey}';
    return '${days.length}天×$width（${layout.label}）$span';
  }
}
