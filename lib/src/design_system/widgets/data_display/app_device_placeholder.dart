import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';

class AppDevicePlaceholder extends StatelessWidget {
  const AppDevicePlaceholder({
    required this.hasPlant,
    super.key,
    this.width = 106,
  });

  final bool hasPlant;
  final double width;

  @override
  Widget build(BuildContext context) {
    final baseHeight = hasPlant ? 164.0 : 106.0;
    return Semantics(
      label: hasPlant ? '植物设备图片占位' : '未添加植物的设备图片占位',
      image: true,
      child: SizedBox(
        width: width,
        height: baseHeight * width / 106,
        child: CustomPaint(
          painter: _DevicePlaceholderPainter(hasPlant: hasPlant),
        ),
      ),
    );
  }
}

class _DevicePlaceholderPainter extends CustomPainter {
  const _DevicePlaceholderPainter({required this.hasPlant});

  final bool hasPlant;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 106;
    canvas.save();
    canvas.scale(scale, scale);

    final height = size.height / scale;
    final potBottom = height - 7;
    final potTop = hasPlant ? potBottom - 78 : potBottom - 96;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(53, potBottom + 1),
        width: hasPlant ? 76 : 94,
        height: 10,
      ),
      Paint()..color = const Color(0x1F252525),
    );

    if (hasPlant) {
      _paintPlant(canvas, potTop + 7);
    }

    final potPath = Path()
      ..moveTo(hasPlant ? 18 : 7, potTop + 12)
      ..cubicTo(18, potTop - 1, 88, potTop - 1, hasPlant ? 88 : 99, potTop + 12)
      ..lineTo(hasPlant ? 86 : 96, potBottom - 25)
      ..cubicTo(84, potBottom - 4, 70, potBottom, 53, potBottom)
      ..cubicTo(36, potBottom, 22, potBottom - 4, 20, potBottom - 25)
      ..close();
    canvas.drawPath(potPath, Paint()..color = const Color(0xFFE4BCBE));

    final highlight = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          Color(0x30FFFFFF),
          Color(0x00FFFFFF),
          Color(0x18000000),
        ],
      ).createShader(Rect.fromLTWH(12, potTop, 84, potBottom - potTop));
    canvas.drawPath(potPath, highlight);

    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(25, potTop + 20, 56, 42),
      const Radius.circular(15),
    );
    canvas.drawRRect(panel, Paint()..color = const Color(0xFF171719));
    _paintFace(canvas, potTop);

    canvas.drawLine(
      Offset(20, potBottom - 27),
      Offset(86, potBottom - 27),
      Paint()
        ..color = const Color(0x267D5055)
        ..strokeWidth = .8,
    );
    canvas.restore();
  }

  void _paintPlant(Canvas canvas, double potTop) {
    final stemPaint = Paint()
      ..color = const Color(0xFF356B3E)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final end in const <Offset>[
      Offset(24, 27),
      Offset(38, 10),
      Offset(53, 3),
      Offset(68, 12),
      Offset(84, 28),
      Offset(19, 48),
      Offset(87, 49),
      Offset(52, 30),
    ]) {
      canvas.drawLine(Offset(53, potTop + 12), end, stemPaint);
    }

    const leaves = <(Offset, double, double)>[
      (Offset(22, 24), 24, -0.35),
      (Offset(38, 10), 24, -1.15),
      (Offset(54, 5), 25, -1.45),
      (Offset(69, 14), 27, -0.62),
      (Offset(85, 30), 24, -0.08),
      (Offset(18, 47), 27, 2.95),
      (Offset(36, 38), 28, -2.75),
      (Offset(54, 29), 29, -1.3),
      (Offset(73, 40), 29, -0.22),
      (Offset(88, 51), 24, 0.28),
      (Offset(47, 55), 27, 2.2),
      (Offset(65, 58), 25, 0.85),
    ];
    for (var index = 0; index < leaves.length; index++) {
      final leaf = leaves[index];
      _paintLeaf(
        canvas,
        leaf.$1,
        leaf.$2,
        leaf.$3,
        index.isEven ? const Color(0xFF3F7444) : const Color(0xFF568A50),
      );
    }
  }

  void _paintLeaf(
    Canvas canvas,
    Offset center,
    double length,
    double angle,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(-length / 2, 0)
      ..quadraticBezierTo(0, -length * .32, length / 2, 0)
      ..quadraticBezierTo(0, length * .32, -length / 2, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset(-length * .36, 0),
      Offset(length * .35, 0),
      Paint()
        ..color = AppColors.surface.withValues(alpha: .42)
        ..strokeWidth = .8,
    );
    canvas.restore();
  }

  void _paintFace(Canvas canvas, double potTop) {
    final eyePaint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(35, potTop + 28, 9, 8),
      3.35,
      2.5,
      false,
      eyePaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(62, potTop + 28, 9, 8),
      3.35,
      2.5,
      false,
      eyePaint,
    );
    canvas.drawCircle(
      Offset(35, potTop + 42),
      4,
      Paint()..color = const Color(0xFFFF5E68),
    );
    canvas.drawCircle(
      Offset(71, potTop + 42),
      4,
      Paint()..color = const Color(0xFFFF5E68),
    );
    final smile = Path()
      ..moveTo(39, potTop + 42)
      ..quadraticBezierTo(53, potTop + 58, 67, potTop + 42)
      ..close();
    canvas.drawPath(smile, Paint()..color = AppColors.surface);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(53, potTop + 69), width: 6, height: 4),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFF6E0D5),
    );
  }

  @override
  bool shouldRepaint(_DevicePlaceholderPainter oldDelegate) =>
      oldDelegate.hasPlant != hasPlant;
}
