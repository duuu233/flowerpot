import 'package:flutter/foundation.dart';

abstract final class ApiConfig {
  /// 临时联调地址（2026-08-29 起）。
  ///
  /// TODO(联调): 上线前必须删除 [_temporaryBaseUrl] 及其回落逻辑，改回只读
  /// `API_BASE_URL`。正式域名 `https://api.yikaltd.com` 目前 443 端口 TLS
  /// 被重置、80 端口返回 403，只有这台机器的明文端口可用，所以先写死 IP 让
  /// 真实短信链路跑通。配套的 Android network-security-config 与 iOS ATS
  /// 例外同样是临时的，要一起回滚。
  static const String _temporaryBaseUrl = 'http://120.25.227.36:8601';

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// `--dart-define=API_BASE_URL=...` 仍然优先，方便后端给出可用 HTTPS 域名后
  /// 不改代码直接切换。
  static String get baseUrl =>
      _envBaseUrl.trim().isEmpty ? _temporaryBaseUrl : _envBaseUrl;

  static const Duration timeout = Duration(seconds: 10);
  static const Duration uploadTimeout = Duration(seconds: 20);
  static const int networkRetryMax = 2;
  static const Duration networkRetryDelay = Duration(milliseconds: 500);

  static int get terminal => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 2,
    _ => 1,
  };
}
