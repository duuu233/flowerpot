import 'mower_current_plan.dart';

/// 工作时间倒计时（2026-10-26 起以设备 DP121 为准，V3.0 §3.8；2026-10-30 起显示在首页计划卡，不在状态胶囊）。
///
/// 终点 = 收到 DP121 新帧时的本机时刻 + 该帧 `et − now`，之后按本机时钟逐分钟递减；收到新帧才
/// 重设基准（机器校时、计划变化、60s 兜底都会重发）。用的是设备给的相对差值，手机时钟快慢、
/// 换手机、重装或另一台手机启动都不影响；不再按「DP119 下发成功」在本机计时，也不在本机存终点。
/// - 显示与否只看 DP121 算出的剩余（2026-10-26 产品）：无计划（st/et=0）或剩余为 0 隐藏，与 DP5 状态、
///   关机、在线无关（`MowerDevice.visibleWorkEndsAt`）；
/// - APP 下发 DP119 成功后先显示图标 + 转圈，等到新的 DP121 计划再显示时间（`MowerDevice.awaitingWorkPlan`）。
class MowerWorkCountdown {
  const MowerWorkCountdown._();

  /// 按一帧 DP121 和收到它的本机时刻算终点；无计划为 null。
  static DateTime? endsAt(MowerCurrentPlan plan, DateTime receivedAt) =>
      plan.active
      ? receivedAt.add(Duration(seconds: plan.remainingSeconds))
      : null;

  /// 剩余整分钟，向上取整：刚设置 2 小时显示「2小时0分」，最后不足 1 分钟仍显示「1分」，
  /// 到点才是 0；过了终点停在 0。
  static int remainingMinutes(DateTime endsAt, DateTime now) {
    final micros = endsAt.difference(now).inMicroseconds;
    if (micros <= 0) return 0;
    const minute = Duration.microsecondsPerMinute;
    return (micros + minute - 1) ~/ minute;
  }

  /// 距离显示值下一次减 1 还有多久；已经是 0 返回 null（不再刷新）。
  static Duration? untilNextTick(DateTime endsAt, DateTime now) {
    final minutes = remainingMinutes(endsAt, now);
    if (minutes == 0) return null;
    return endsAt.difference(now) - Duration(minutes: minutes - 1);
  }

  /// 首页计划卡显示「手动计划」还是「今日计划」（2026-10-30 产品，协议 §3.8 推荐写法）：
  /// 先看倒计时，为 0（含无计划、没报过 DP121）直接今日计划，不再看 DP121 类型；
  /// 大于 0 才按 `t`，手动计划（2）显示手动计划，其余显示今日计划。
  static bool showsManualPlan({
    required MowerCurrentPlan? plan,
    required DateTime? endsAt,
    required DateTime now,
  }) {
    if (endsAt == null || remainingMinutes(endsAt, now) == 0) return false;
    return switch (plan?.type) {
      MowerPlanType.manual => true,
      _ => false,
    };
  }

  /// 「1小时59分」/ 不足 1 小时「45分」/ 到点「0分」。
  static String label(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return hours > 0 ? '$hours小时$rest分' : '$rest分';
  }
}
