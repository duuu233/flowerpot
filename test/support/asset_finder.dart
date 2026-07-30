import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder findAssetImage(String assetPath) {
  return find.byWidgetPredicate((widget) {
    if (widget is! Image) return false;
    final provider = widget.image;
    return provider is AssetImage && provider.assetName == assetPath;
  }, description: 'Image using asset $assetPath');
}
