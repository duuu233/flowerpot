import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

class HomeOrbitDecoration extends StatelessWidget {
  const HomeOrbitDecoration({super.key, this.size = 252});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFDBF5F7)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x2870AFB5), blurRadius: 32),
                ],
              ),
            ),
          ),
          Positioned(top: size * .08, left: size * .20, child: const _Node()),
          Positioned(top: size * .58, right: -1, child: const _Node()),
          Positioned(
            bottom: size * .08,
            left: size * .19,
            child: const _Node(),
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: const Color(0xFF7DEBF0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x667DEBF0), blurRadius: 5),
        ],
      ),
    );
  }
}
