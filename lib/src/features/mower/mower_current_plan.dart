import 'dart:convert';

/// DP121 计划类型 `t`（协议 V3.1 增量，2026-10-30；MCU_VER ≥ 1.3.5 才带）。
enum MowerPlanType {
  /// `0` 无计划 / 未知；旧固件没有 `t` 字段也按它处理。
  none,

  /// `1` 定时计划：DP101 配置的计划到点自动开工（含中断后继续工作）。
  scheduled,

  /// `2` 手动计划：面板按键 / App 远程启动 / 定点割草（含中断后继续工作）。
  manual;

  static MowerPlanType fromValue(Object? value) => switch (value) {
    1 => scheduled,
    2 => manual,
    _ => none,
  };
}

/// DP121 schedule_current：机器当前计划（V3.0 §3.8，2026-10-26 新增；V3.1 加计划类型 `t`）。
///
/// 设备发的是基准量 `{"st":计划开始,"et":计划结束,"now":本帧构建时的机器时间,"t":计划类型}`（时间均为
/// UTC 秒），不是剩余秒，也不按倒计时上报：只在计划变化、机器校时、App 打开 / 连云全量上报以及兜底
/// （有计划 60s / 无计划 300s）时发。剩余由 App 用 `et − now` 自己算并本地递减。
class MowerCurrentPlan {
  const MowerCurrentPlan({
    required this.startSeconds,
    required this.endSeconds,
    required this.deviceNowSeconds,
    this.type = MowerPlanType.none,
  });

  final int startSeconds;
  final int endSeconds;
  final int deviceNowSeconds;

  /// 计划类型；旧固件（≤ 1.3.4）没有 `t`，按 [MowerPlanType.none]。
  final MowerPlanType type;

  /// st / et / now 是 u32，缺字段、负数、超范围或不是整数都整帧作废。
  /// `t` 缺字段或认不出按 0（协议 §3.8：缺 `t` 不能当解析失败）。
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
        type: MowerPlanType.fromValue(data['t']),
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

  /// 计划身份看 (st, et, t)：`now` 每帧都变，不代表计划变了；手动启动与定时计划可能撞出同一时段，
  /// 只有 `t` 变也算计划变了（V3.1 注意事项 13 / 15）。
  bool samePlan(MowerCurrentPlan? other) =>
      other != null &&
      other.startSeconds == startSeconds &&
      other.endSeconds == endSeconds &&
      other.type == type;

  /// 同一帧（快照反复刷进来的是同一个值）：四个字段都相同。
  bool sameFrame(MowerCurrentPlan? other) =>
      samePlan(other) && other!.deviceNowSeconds == deviceNowSeconds;
}
