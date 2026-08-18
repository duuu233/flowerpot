import 'package:flutter/material.dart';

class AuthAssetIcon extends StatelessWidget {
  const AuthAssetIcon({
    required this.assetPath,
    this.size = 24,
    this.offsetX = 0,
    super.key,
  });

  final String assetPath;
  final double size;

  /// Horizontal nudge in logical pixels, applied without changing the 48pt
  /// slot the field reserves for the icon.
  final double offsetX;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Center(
        child: Transform.translate(
          offset: Offset(offsetX, 0),
          child: Image.asset(
            assetPath,
            key: ValueKey<String>('auth-asset-icon:$assetPath'),
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
