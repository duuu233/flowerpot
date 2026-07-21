import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class AccountPasswordFormCard extends StatelessWidget {
  const AccountPasswordFormCard({required this.fields, super.key});

  final List<AccountPasswordField> fields;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      padding: EdgeInsets.zero,
      showShadow: false,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var index = 0; index < fields.length; index++) ...<Widget>[
              fields[index],
              if (index < fields.length - 1)
                const Divider(indent: 22, endIndent: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class AccountPasswordField extends StatelessWidget {
  const AccountPasswordField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.visible,
    required this.visibilityKey,
    required this.onVisibilityChanged,
    required this.textInputAction,
    super.key,
    this.icon = Icons.lock_outline_rounded,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final bool visible;
  final Key visibilityKey;
  final VoidCallback onVisibilityChanged;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 22),
          AppIconBadge(
            icon: icon,
            color: AppColors.brandPrimary,
            backgroundColor: AppColors.brandSurface,
            size: 40,
            iconSize: 23,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppTypography.sectionTitle.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                SizedBox(
                  height: 27,
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: textInputAction,
                    obscureText: !visible,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: autofillHints,
                    onSubmitted: onSubmitted,
                    style: AppTypography.body.copyWith(
                      fontSize: 15,
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        height: 1.2,
                      ),
                      isDense: true,
                      filled: false,
                      contentPadding: const EdgeInsets.only(top: 2),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: visibilityKey,
            tooltip: visible ? '隐藏密码' : '显示密码',
            onPressed: onVisibilityChanged,
            icon: visible
                ? const Icon(
                    Icons.visibility_outlined,
                    color: AppColors.textSecondary,
                    size: 21,
                  )
                : const SizedBox.square(
                    dimension: 22,
                    child: CustomPaint(painter: _ClosedEyePainter()),
                  ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _ClosedEyePainter extends CustomPainter {
  const _ClosedEyePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final eye = Path()
      ..moveTo(size.width * .18, size.height * .44)
      ..quadraticBezierTo(
        size.width * .50,
        size.height * .75,
        size.width * .82,
        size.height * .44,
      );
    canvas.drawPath(eye, paint);
    canvas.drawLine(
      Offset(size.width * .25, size.height * .59),
      Offset(size.width * .19, size.height * .76),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * .50, size.height * .68),
      Offset(size.width * .50, size.height * .86),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * .75, size.height * .59),
      Offset(size.width * .81, size.height * .76),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ClosedEyePainter oldDelegate) => false;
}
