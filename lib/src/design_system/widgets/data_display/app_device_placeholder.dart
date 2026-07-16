import 'package:flutter/material.dart';

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
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 106,
            height: baseHeight,
            child: Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: hasPlant ? 84 : 106,
                    height: hasPlant ? 92 : 106,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9C9C6),
                      borderRadius: BorderRadius.circular(hasPlant ? 30 : 28),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x20252525),
                          blurRadius: 12,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasPlant)
                  Container(
                    width: 104,
                    height: 86,
                    decoration: const BoxDecoration(
                      color: Color(0xFF7AA66E),
                      borderRadius: BorderRadius.all(Radius.circular(42)),
                    ),
                  )
                else
                  Positioned(
                    top: 15,
                    child: Container(
                      width: 78,
                      height: 51,
                      decoration: BoxDecoration(
                        color: const Color(0xFF202020),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
