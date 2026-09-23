import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../mower_ui.dart';

/// 首页那圈电量环 + 整机图 + 环下面那行电量 + 状态胶囊。
///
/// 稿子上这一块没有卡片底（`设备状态卡片` 的 fills 是空的，只留了一层投影），所以
/// 这里也不画底，直接落在页面渐变上。四种电量态（[MowerPowerState]）换的只是环的
/// 两个颜色和环下面那行字。
class MowerStatusCard extends StatelessWidget {
  const MowerStatusCard({
    required this.tone,
    required this.percent,
    required this.statusLabel,
    super.key,
    this.onTapRing,
    this.wifiLinked = false,
    this.bleLinked = false,
  });

  /// Wi-Fi / 蓝牙图标亮不亮：各自读涂鸦的分通道状态（2026-09-23），同时连着就都亮。
  final bool wifiLinked;
  final bool bleLinked;

  /// 视觉态，由 DP13（电量）与 DP117（充电状态）换算，见 `MowerControlPage._tone`。
  final MowerPowerState tone;

  /// DP13 电量。
  final int percent;

  /// DP5 工作状态，画在状态胶囊里。
  final String statusLabel;

  final VoidCallback? onTapRing;

  /// 环的直径，和稿子一致（263）。
  static const double ringSize = 263;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 292,
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          Positioned(
            top: 0,
            child: GestureDetector(
              key: const Key('mower-battery-ring'),
              onTap: onTapRing,
              behavior: HitTestBehavior.opaque,
              child: SizedBox.square(
                dimension: ringSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    CustomPaint(
                      size: const Size.square(ringSize),
                      painter: _MowerRingPainter(
                        progress: percent / 100,
                        color: tone.ringColor,
                        trackColor: tone.ringTrackColor,
                      ),
                    ),
                    // 整机图比环心低 8 px（稿子上它压在环的下半圈里）。
                    Transform.translate(
                      offset: const Offset(0, 8),
                      child: Image.asset(
                        MowerAssets.device,
                        width: 182,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(top: 222, child: _BatteryLine(tone: tone, percent: percent)),
          Positioned(
            top: 256,
            child: _StatusChips(
              label: statusLabel,
              wifiLinked: wifiLinked,
              bleLinked: bleLinked,
            ),
          ),
        ],
      ),
    );
  }
}

/// 环下面那行：默认态只有「电量 78%」，其余三态是「图标 + 状态词 + 百分比」。
class _BatteryLine extends StatelessWidget {
  const _BatteryLine({required this.tone, required this.percent});

  final MowerPowerState tone;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final label = tone.statusLabel;
    if (label == null) {
      return Text(
        '电量 $percent%',
        key: const Key('mower-battery-label'),
        style: const TextStyle(
          color: MowerColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    const textStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    return Row(
      key: const Key('mower-battery-label'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 充电态图标背后原有一圈光晕（稿子 `充电动效 / 光晕`），2026-09-23 产品要求去掉。
        SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Image.asset(
              tone.statusIcon!,
              width: 22,
              height: 16,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
        ),
        const SizedBox(width: 5),
        // 状态词和百分比放进**同一个 Text** 的两段，共用一条基线（2026-09-23 产品：「电量告警」
        // 「30%」没对齐）。原来是 Row 里两个 Text 各自按方框居中：中文和数字走的是不同字体，
        // 字框高度 / 基线位置不一样，居中后就上下错开。
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: label,
                style: textStyle.copyWith(color: tone.statusColor),
              ),
              TextSpan(
                text: ' $percent%',
                style: textStyle.copyWith(color: MowerColors.ink),
              ),
            ],
          ),
          key: const Key('mower-battery-status-text'),
        ),
      ],
    );
  }
}

/// 状态胶囊 + 两颗连接图标。稿子上它们压在环的下沿上。
///
/// 胶囊里的字是 **DP5 工作状态**（待机 / 割草中 / 已暂停 / 回桩中…），不是写死的「待机」。
class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.label,
    required this.wifiLinked,
    required this.bleLinked,
  });

  final String label;
  final bool wifiLinked;
  final bool bleLinked;

  /// 没连的那颗压淡（稿子只给了亮的图，灭的就按 30% 画）。
  static Widget _linkIcon(String asset, {required bool on, required Key key}) =>
      Opacity(
        key: key,
        opacity: on ? 1 : .3,
        child: Image.asset(
          asset,
          width: 26,
          height: 26,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: MowerColors.chipFill,
            borderRadius: BorderRadius.all(Radius.circular(30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox.square(
                dimension: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MowerColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                key: const Key('mower-status-chip'),
                style: const TextStyle(
                  color: MowerColors.brand,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _linkIcon(
          MowerAssets.wifiIcon,
          on: wifiLinked,
          key: Key('mower-link-wifi-${wifiLinked ? 'on' : 'off'}'),
        ),
        const SizedBox(width: 10),
        _linkIcon(
          MowerAssets.bluetoothIcon,
          on: bleLinked,
          key: Key('mower-link-ble-${bleLinked ? 'on' : 'off'}'),
        ),
      ],
    );
  }
}

/// 电量环：底下留一道缺口的仪表盘，从左下角（135°）顺时针走 270°。
///
/// 稿子上两端的位置量出来是 137° 和 42.8°（顺时针跨 266°），取整到 135° / 270°：
/// 整数角度画出来两端对称，肉眼和稿子对不出差别。
class _MowerRingPainter extends CustomPainter {
  const _MowerRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  static const double _startAngle = math.pi * 0.75;
  static const double _sweepAngle = math.pi * 1.5;
  static const double _strokeWidth = 14;

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(_strokeWidth / 2, _strokeWidth / 2) &
        Size(size.width - _strokeWidth, size.height - _strokeWidth);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawArc(
        rect,
        _startAngle,
        _sweepAngle,
        false,
        base..color = trackColor,
      )
      ..drawArc(
        rect,
        _startAngle,
        _sweepAngle * progress.clamp(0, 1),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
  }

  @override
  bool shouldRepaint(_MowerRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
