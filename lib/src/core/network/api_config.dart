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

  /// 显式禁用 APP 后端的哨兵值：`--dart-define=API_BASE_URL=none`。
  ///
  /// [_temporaryBaseUrl] 写死之后，"不配地址就走纯涂鸦链路" 这个调试模式没法
  /// 用了 —— 传空值也会被回落逻辑顶回写死的地址。这个哨兵值把它还回来，用于
  /// 排查绑在涂鸦原生账号（手机号直接注册）下的设备，不必改源码再改回去。
  static const String disabledMarker = 'none';

  /// `--dart-define=API_BASE_URL=...` 优先，方便后端给出可用 HTTPS 域名后不改
  /// 代码直接切换；传 [disabledMarker] 则禁用 REST 后端。
  static String get baseUrl {
    final configured = _envBaseUrl.trim();
    if (configured.isEmpty) return _temporaryBaseUrl;
    if (configured.toLowerCase() == disabledMarker) return '';
    return configured;
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
