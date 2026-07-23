import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');
  static const Duration timeout = Duration(seconds: 10);
  static const Duration uploadTimeout = Duration(seconds: 20);
  static const int networkRetryMax = 2;
  static const Duration networkRetryDelay = Duration(milliseconds: 500);

  static int get terminal => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 2,
    _ => 1,
  };
}
