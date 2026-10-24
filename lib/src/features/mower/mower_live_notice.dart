import 'dart:async';

import 'mower_dp.dart';
import 'mower_fault_alarm.dart';

/// 首页黄条上的实时提醒：抬起 / 落地、陷坑脱困（2026-10-22 检查报告第 5、6 节）。
///
/// 来源（协议 V3.0）：
/// - 抬起：DP111 `circularize` 层的实时抬起位 [liftBit]（变化即报，60 秒兜底），
///   与 DP120 事件码 44 / 144 互为补充——谁先到用谁，状态没变就不重复提示；
/// - 陷坑脱困：只跟 DP5 = 12 `escaping`（[onStatus]，2026-10-24 用户选定）。DP5 每秒兜底重报，
///   快照同样算数：DP5 是 12 就显示，变成别的值就收起（成功回原作业、困死转 6 故障、急停转 7）。
///   DP120 41 / 141 只记日志，不再驱动黄条，也没有超时收起；困死后由 DP18 故障文案接替（黄条故障优先）。
///
/// 抬起只认实时上报（[onFaultAlarm] / [onEvent]）；刚进页面读到的快照只用 [baseline] 同步「是否抬着」，
/// 快照里那条旧事件码不触发提示，也不补「已落地」。
class MowerLiveNotice {
  MowerLiveNotice(this._onTimeout);

  /// 定时收起时通知页面重画（实时上报引起的变化由调用方自己通知）。
  final void Function() _onTimeout;

  /// DP111 `circularize` bit12 MOWER_LIFT（V3.0 §3.4）。
  static const int liftBit = 0x1000;

  /// 「设备已落地」显示几秒后自动收起。
  static const Duration landedVisible = Duration(seconds: 3);

  static const String liftedText = '设备已抬起';
  static const String landedText = '设备已落地';
  static const String trapEscapingText = '机器陷入坑洼，正在脱困';

  bool _lifted = false;
  bool _landed = false;
  bool _trapEscaping = false;
  Timer? _landedTimer;

  /// 此刻黄条该显示的那句；没有为 null。抬起 / 落地优先于脱困。
  String? get message {
    if (_lifted) return liftedText;
    if (_landed) return landedText;
    if (_trapEscaping) return trapEscapingText;
    return null;
  }

  /// 刚绑定时按快照同步是否抬着，不弹「已落地」。
  void baseline(MowerFaultAlarm? alarm) {
    _clearTimers();
    _landed = false;
    _lifted = alarm != null && (alarm.circularize & liftBit) != 0;
  }

  /// 实时 DP111。
  void onFaultAlarm(MowerFaultAlarm alarm) =>
      _setLifted((alarm.circularize & liftBit) != 0);

  /// 当前 DP5（快照与实时上报都算）。返回提示有没有变。
  bool onStatus(MowerStatus status) {
    final before = message;
    _trapEscaping = status == MowerStatus.escaping;
    return message != before;
  }

  /// 实时 DP120 事件码，只认抬起 44 / 落地 144。返回这一码有没有改变提示。
  bool onEvent(int code) {
    final before = message;
    switch (code) {
      case 44:
        _setLifted(true);
      case 144:
        _setLifted(false);
    }
    return message != before;
  }

  void reset() {
    _clearTimers();
    _lifted = false;
    _landed = false;
    _trapEscaping = false;
  }

  void _setLifted(bool lifted) {
    if (lifted == _lifted) return;
    _lifted = lifted;
    _landedTimer?.cancel();
    _landedTimer = null;
    _landed = !lifted;
    if (_landed) {
      _landedTimer = Timer(landedVisible, () {
        _landed = false;
        _onTimeout();
      });
    }
  }

  void _clearTimers() {
    _landedTimer?.cancel();
    _landedTimer = null;
  }
}
