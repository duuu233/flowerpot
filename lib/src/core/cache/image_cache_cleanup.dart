import 'package:flutter/painting.dart';

/// Clears account-scoped decoded images after logout or account deletion.
abstract final class ImageCacheCleanup {
  static void clearAll() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }
}
