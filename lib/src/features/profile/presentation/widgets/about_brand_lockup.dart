import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import '../../models/about_page_model.dart';

class AboutBrandLockup extends StatelessWidget {
  const AboutBrandLockup({required this.model, super.key});

  final AboutPageModel model;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('about-brand-lockup'),
      children: <Widget>[
        const _AboutLogoMark(),
        const SizedBox(height: AppSpacing.xl),
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Text(
              model.appName,
              style: AppTypography.emptyStateTitle.copyWith(
                color: AppColors.textStrong,
                fontSize: 35,
                fontWeight: FontWeight.w700,
                height: 1.1,
                letterSpacing: -1.2,
              ),
            ),
            const Positioned(
              top: -3,
              right: 43,
              child: Icon(
                Icons.eco_rounded,
                size: 15,
                color: AppColors.brandPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          model.tagline,
          style: AppTypography.status.copyWith(
            color: AppColors.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _AboutLogoMark extends StatelessWidget {
  const _AboutLogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('about-logo-placeholder'),
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFCDEAE6), AppColors.brandPrimary],
        ),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: const CustomPaint(painter: _LogoMarkPainter()),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  const _LogoMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final pot = Path()
      ..moveTo(18, 43)
      ..lineTo(42, 43)
      ..lineTo(39, 53)
      ..quadraticBezierTo(38.5, 55, 36, 55)
      ..lineTo(24, 55)
      ..quadraticBezierTo(21.5, 55, 21, 53)
      ..close();
    canvas.drawPath(pot, paint);
    canvas.drawLine(const Offset(30, 43), const Offset(30, 16), stroke);

    final leftLeaf = Path()
      ..moveTo(29, 25)
      ..quadraticBezierTo(17, 25, 15, 16)
      ..quadraticBezierTo(26, 15, 29, 25)
      ..close();
    final rightLeaf = Path()
      ..moveTo(31, 21)
      ..quadraticBezierTo(36, 10, 48, 11)
      ..quadraticBezierTo(43, 22, 31, 21)
      ..close();
    canvas.drawPath(leftLeaf, paint);
    canvas.drawPath(rightLeaf, paint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'YS',
        style: TextStyle(
          color: AppColors.surface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, const Offset(19, 25));
  }

  @override
  bool shouldRepaint(covariant _LogoMarkPainter oldDelegate) => false;
}
