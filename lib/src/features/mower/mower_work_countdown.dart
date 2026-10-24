import 'package:shared_preferences/shared_preferences.dart';

/// 工作时间倒计时（2026-10-22 产品定稿，见 `docs/reports/2026-10-22-割草机倒计时与雨滴陷坑抬起检查.md`）。
///
/// 设备没有「剩余作业时间」DP，倒计时完全由 APP 按「DP119 下发成功的时刻 + 下发的小时数」计算，
/// 与设备实际是否还在割草无关：
/// - 不暂停：停止、急停、故障、回充、在桩等待都照常递减；
/// - 不隐藏：设置后一直显示，减到 0 停在「0分」；
/// - 重设即重跑：再次下发 DP119 成功就用新的终点，旧的作废；「继续」不重写 DP119，不重计。
///
/// 终点只记在本机（按设备 ID 存 [SharedPreferences]）：换手机、重装或别的手机设置的时间无从得知，
/// 这时 [load] 返回 null，首页不显示倒计时，不编时间。
class MowerWorkCountdown {
  const MowerWorkCountdown._();

  static String _key(String deviceId) => 'mower_work_ends_at_$deviceId';

  /// 本机记过的终点；没记过或读失败为 null。
  static Future<DateTime?> load(String deviceId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final millis = preferences.getInt(_key(deviceId));
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    } on Object {
      return null;
    }
  }

  static Future<void> save(String deviceId, DateTime endsAt) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(
        _key(deviceId),
        endsAt.millisecondsSinceEpoch,
      );
    } on Object {
      // 存不下只影响重进页面后的显示，本次会话仍按内存里的终点显示。
    }
  }

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

  /// 「1小时59分」/ 不足 1 小时「45分」/ 到点「0分」。
  static String label(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return hours > 0 ? '$hours小时$rest分' : '$rest分';
  }
}
