import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';

/// Keeps a direct route back to the temporary page catalogue above every
/// previewed screen, including screens opened from another previewed screen.
class PreviewReturnOverlay extends StatelessWidget {
  const PreviewReturnOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        Positioned(
          right: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 12,
          child: Semantics(
            button: true,
            label: '返回临时页面目录',
            child: Material(
              color: const Color(0xFF173F35),
              elevation: 8,
              shadowColor: const Color(0x66112620),
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('preview-return-button'),
                onTap: () => Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.root, (_) => false),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.keyboard_return_rounded,
                        color: Color(0xFFF4F0DE),
                        size: 18,
                      ),
                      SizedBox(width: 7),
                      Text(
                        '返回目录',
                        style: TextStyle(
                          color: Color(0xFFF4F0DE),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
