import '../../../tuya/tuya_history_codec.dart';
import '../../../tuya/tuya_models.dart';

/// 四个状态页那条日期切换条（`DateRangeNavigator`）的**窗口规则**，一处定义、四页共用。
///
/// ⚠️ **往前翻必须有下限**（2026-09-17 用户实测报的 BUG：「历史数据日期可以无限调」）。
/// 四个页面原来的 `onPrevious` 都是裸的 `periodOffset--`，一直点能翻到去年——而设备
/// 根本没有那些天的数据，翻过去只是标签在动。往后翻本来就有界（`periodOffset < 0`），
/// 坏的一直只有往前这一侧。
///
/// 窗口不是 UI 口味，是**设备一次到底给了多少**决定的，所以这张表跟着
/// [TuyaHistoryCodec.maxDailyWindow] 走，不另写一个数字。
abstract final class HistoryPeriod {
  /// 这个周期最多往前翻几期。
  ///
  /// - **日：6** —— 当天 + 往前 6 天 = 7 天，就是设备日包一次带的天数
  ///   （[TuyaHistoryCodec.maxDailyWindow]，2026-09-17 固件）。
  /// - **周 / 月：0** —— 设备的周包 / 月包**只有当期这一份**（132/133、135/136、
  ///   138/139 各一条 DP 就是一整期，滚动覆盖），往前没有第二份可取。
  static int maxBack(ReportRange range) => switch (range) {
    ReportRange.day => TuyaHistoryCodec.maxDailyWindow - 1,
    ReportRange.week => 0,
    ReportRange.month => 0,
  };

  /// 还能不能往前翻。[offset] 就是页面的 `periodOffset`（0 = 当期，负数往前）。
  static bool canGoBack(ReportRange range, int offset) =>
      offset > -maxBack(range);

  /// 还能不能往后翻：当期就是最右边，没有「明天」可看。
  static bool canGoForward(int offset) => offset < 0;

  /// 日视图里 [offset] 对应的那一天，只到日、不带时分。
  ///
  /// 用 `DateTime` 构造函数进位（`day + offset` 越界自动跨月跨年），**不用**
  /// `add(Duration(days:))`——夏令时那天加 24 小时会落到前一天的 23 点。
  static DateTime dayFor(int offset) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + offset);
  }

  // ── 周 / 月：只标相对刻度（docs/app_DP_问题修正说明.md §4.5 第 3 条）──
  //
  // 周包 / 月包的点数是「已聚合天数」，设备断过电就会缺天；**右端对齐**，最后一个点是
  // 最近一次聚合日（通常是昨天，不是今天）。所以横轴不标具体日期 / 星期，只标「N天前」，
  // 第 i 个点按 `点数 − i` 天前算。

  /// 第 [index] 个点（共 [count] 个）的相对标签。
  static String relativeDayLabel(int index, int count) {
    final daysAgo = count - index;
    return daysAgo <= 1 ? '昨天' : '$daysAgo天前';
  }

  /// 折线图用的均匀刻度（标签在图上等距铺开）：从最老一点到最新一点取 [ticks] 个。
  static List<String> relativeTicks(int count, {int ticks = 5}) {
    if (count <= 0) return const <String>[];
    if (count <= ticks) {
      return <String>[
        for (var i = 0; i < count; i++) relativeDayLabel(i, count),
      ];
    }
    return <String>[
      for (var tick = 0; tick < ticks; tick++)
        relativeDayLabel(((count - 1) * tick / (ticks - 1)).round(), count),
    ];
  }

  /// 柱状图用的逐柱标签：每隔 [every] 根标一个，最后一根一定标，其余留空。
  static List<String> relativeBarLabels(int count, {int every = 7}) => <String>[
    for (var i = 0; i < count; i++)
      i == count - 1 || (count - 1 - i) % every == 0
          ? relativeDayLabel(i, count)
          : '',
  ];

  /// 日期条上的标题：周 / 月只说窗口，不写日期区间。
  static String windowLabel(ReportRange range, int count) => switch (range) {
    ReportRange.day => '',
    ReportRange.week => count > 0 ? '近 $count 天日均' : '近 4 周',
    ReportRange.month => count > 0 ? '近 $count 天日均' : '近半年',
  };
}
