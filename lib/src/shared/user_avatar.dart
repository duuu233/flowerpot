import 'dart:io';

import 'package:flutter/widgets.dart';

/// Resolves a stored avatar path into an image provider.
///
/// [AppUser.avatarUrl] holds either a local file path picked on the device or
/// a remote URL, so both have to be handled before falling back to the
/// placeholder icon.
ImageProvider<Object>? resolveUserAvatar(String? path) {
  final value = path?.trim();
  if (value == null || value.isEmpty) return null;
  // Bundled artwork, used by the demo account.
  if (value.startsWith('assets/')) return AssetImage(value);
  final file = File(value);
  if (file.existsSync()) return FileImage(file);
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return NetworkImage(value);
  }
  return null;
}
