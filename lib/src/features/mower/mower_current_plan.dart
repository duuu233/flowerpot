import 'dart:convert';

/// DP121 schedule_current：机器当前计划（V3.0 §3.8，2026-10-26 新增）。
///
/// 设备发的是基准量 `{"st":计划开始,"et":计划结束,"now":本帧构建时的机器时间}`（均为 UTC 秒），
/// 不是剩余秒，也不按倒计时上报：只在计划变化、机器校时、App 打开 / 连云全量上报以及兜底
/// （有计划 60s / 无计划 300s）时发。剩余由 App 用 `et − now` 自己算并本地递减。
class MowerCurrentPlan {
  const MowerCurrentPlan({
    required this.startSeconds,
    required this.endSeconds,
    required this.deviceNowSeconds,
  });

  final int startSeconds;
  final int endSeconds;
  final int deviceNowSeconds;

  /// u32 字段，缺字段、负数、超范围或不是整数都整帧作废。
  static MowerCurrentPlan? parse(Object? raw) {
    try {
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map) return null;
      final values = <int>[];
      for (final key in ['st', 'et', 'now']) {
        final value = data[key];
        if (value is! int || value < 0 || value > 0xffffffff) return null;
        values.add(value);
      }
      return MowerCurrentPlan(
        startSeconds: values[0],
        endSeconds: values[1],
        deviceNowSeconds: values[2],
      );
    } on FormatException {
      return null;
    }
  }

  /// 有计划：起止都不为 0 且结束晚于开始。无计划时设备发 st=et=0。
  bool get active => startSeconds > 0 && endSeconds > startSeconds;

  /// 本帧时刻的剩余秒数：`max(0, et − now)`；无计划为 0。
  int get remainingSeconds {
    if (!active) return 0;
    final rest = endSeconds - deviceNowSeconds;
    return rest > 0 ? rest : 0;
  }

  /// 计划身份只看 (st, et)：`now` 每帧都变，不代表计划变了（V3.0 注意事项 13）。
  bool samePlan(MowerCurrentPlan? other) =>
      other != null &&
      other.startSeconds == startSeconds &&
      other.endSeconds == endSeconds;

  /// 同一帧（快照反复刷进来的是同一个值）：三个字段都相同。
  bool sameFrame(MowerCurrentPlan? other) =>
      samePlan(other) && other!.deviceNowSeconds == deviceNowSeconds;
}
