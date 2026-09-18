import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../mower_demo.dart';

/// 首页那圈电量环 + 整机图 + 环下面那行电量 + 状态胶囊。
///
/// 稿子上这一块没有卡片底（`设备状态卡片` 的 fills 是空的，只留了一层投影），所以
/// 这里也不画底，直接落在页面渐变上。四种电量态（[MowerPowerState]）换的只是环的
/// 两个颜色和环下面那行字。
class MowerStatusCard extends StatelessWidget {
  const MowerStatusCard({required this.state, super.key, this.onTapRing});

  final MowerPowerState state;

  /// 点环切下一种电量态——**排查用**，见 `MowerControlPage`。
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
                        progress: state.percent / 100,
                        color: state.ringColor,
                        trackColor: state.ringTrackColor,
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
          Positioned(top: 222, child: _BatteryLine(state: state)),
          const Positioned(top: 256, child: _StatusChips()),
        ],
      ),
    );
  }
}

/// 环下面那行：默认态只有「电量 78%」，其余三态是「图标 + 状态词 + 百分比」。
class _BatteryLine extends StatelessWidget {
  const _BatteryLine({required this.state});

  final MowerPowerState state;

  @override
  Widget build(BuildContext context) {
    final label = state.statusLabel;
    if (label == null) {
      return Text(
        '电量 ${state.percent}%',
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
        // 充电态图标背后多一圈光晕（`充电动效 / 光晕`）。
        Container(
          alignment: Alignment.center,
          width: 28,
          height: 28,
          decoration: state.showChargingHalo
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: MowerColors.brand.withValues(alpha: .1),
                  border: Border.all(
                    color: MowerColors.brand.withValues(alpha: .5),
                    width: 1.5,
                  ),
                )
              : null,
          child: Image.asset(
            state.statusIcon!,
            width: 22,
            height: 16,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: textStyle.copyWith(color: state.statusColor)),
        const SizedBox(width: 5),
        Text(
          '${state.percent}%',
          style: textStyle.copyWith(color: MowerColors.ink),
        ),
      ],
    );
  }
}

/// 状态胶囊 + 两颗连接图标。稿子上它们压在环的下沿上。
class _StatusChips extends StatelessWidget {
  const _StatusChips();

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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MowerColors.brand,
                  ),
                ),
              ),
              SizedBox(width: 6),
              Text(
                '待机',
                style: TextStyle(
                  color: MowerColors.brand,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Image.asset(
          MowerAssets.wifiIcon,
          width: 26,
          height: 26,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 10),
        Image.asset(
          MowerAssets.bluetoothIcon,
          width: 26,
          height: 26,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
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
