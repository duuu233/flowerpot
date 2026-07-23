import 'package:flutter/material.dart';

class AuthAssetIcon extends StatelessWidget {
  const AuthAssetIcon({required this.assetPath, this.size = 24, super.key});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Center(
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
    );
  }
}
