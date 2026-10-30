import 'dart:async';

import 'package:flutter/material.dart';

import '../../mower_ui.dart';
import '../../mower_work_countdown.dart';

/// 工作时间倒计时：「⏱ 1小时59分」，按分钟递减，减到 0 整块收起（2026-10-26 产品）。
///
/// 2026-10-30 起放在首页计划卡里原来「修边」的位置（状态胶囊后面不再显示）。
/// 只按终点和当前时间算，不判断设备状态。[loading] 时显示图标 + 转圈，等 DP121 计划。
/// 每次只排一个计时器，到下一次显示值变化的那一刻再刷新。
class MowerWorkCountdownView extends StatefulWidget {
  const MowerWorkCountdownView({
    required this.endsAt,
    required this.loading,
    required this.now,
    super.key,
  });

  final DateTime? endsAt;
  final bool loading;
  final DateTime Function() now;

  @override
  State<MowerWorkCountdownView> createState() => _MowerWorkCountdownViewState();
}

class _MowerWorkCountdownViewState extends State<MowerWorkCountdownView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(MowerWorkCountdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt ||
        oldWidget.loading != widget.loading) {
      _schedule();
    }
  }

  void _schedule() {
    _tick?.cancel();
    final endsAt = widget.endsAt;
    final wait = widget.loading || endsAt == null
        ? null
        : MowerWorkCountdown.untilNextTick(endsAt, widget.now());
    _tick = wait == null
        ? null
        : Timer(wait, () {
            if (!mounted) return;
            setState(_schedule);
          });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = widget.endsAt;
    final Widget value;
    if (widget.loading) {
      value = const SizedBox.square(
        key: Key('mower-work-countdown-loading'),
        dimension: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: MowerColors.brand,
        ),
      );
    } else {
      final minutes = endsAt == null
          ? 0
          : MowerWorkCountdown.remainingMinutes(endsAt, widget.now());
      if (minutes == 0) return const SizedBox.shrink();
      value = Text(
        MowerWorkCountdown.label(minutes),
        key: const Key('mower-work-countdown-text'),
        style: _textStyle,
      );
    }
    return Row(
      key: const Key('mower-work-countdown'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.timer_outlined, size: 13, color: MowerColors.brand),
        const SizedBox(width: 2),
        value,
      ],
    );
  }
}

const TextStyle _textStyle = TextStyle(
  color: MowerColors.brand,
  fontSize: 12,
  fontWeight: FontWeight.w500,
);
