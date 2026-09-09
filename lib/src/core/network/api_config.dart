import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL', defaultValue: 'https://api.yikaltd.com',
  );

  static String get baseUrl => validateBaseUrl(_configuredBaseUrl);

  /// Require a secure API origin, never a Swagger page or a disabled backend.
  static String validateBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(value, 'API_BASE_URL', '必须是 HTTPS API 源站');
    }
    return uri.origin;
  }

  static const Duration timeout = Duration(seconds: 10);
  static const Duration uploadTimeout = Duration(seconds: 20);
  static const int networkRetryMax = 2;
  static const Duration networkRetryDelay = Duration(milliseconds: 500);

  static int get terminal => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 2,
    _ => 1,
  };
}
