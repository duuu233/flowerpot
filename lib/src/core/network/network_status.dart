import 'dart:async';
import 'dart:io' show InternetAddress, SocketException;

import 'api_config.dart';

/// 判断手机当前能不能上网 / 后端能不能连；true = 能。
typedef NetworkProbe = Future<bool> Function();

/// 一次失败来自哪边，决定手机有网时要不要提示「服务器异常」。
enum NetworkFailureSource {
  /// APP 后端请求在传输层失败（连不上、超时，重试已用尽）。
  backend,

  /// 涂鸦 SDK 报错：错误码分不出是不是网络问题，手机有网时什么都不提示。
  tuya,
}

/// 「手机现在有没有网」「后端能不能连」的判断，以及「请求因为网络失败了」的全局上报口。
///
/// 「网络异常」弹窗（`NetworkAlertHost`）只在两种时机检查：冷启动 / 回前台，以及
/// 这里收到一次 [reportFailure] 之后。**不常驻监听系统网络变化**——那要接
/// `connectivity_plus` 或原生桥接，本机没有 Flutter / Kotlin 工具链验证不了；
/// 用户真正受影响的时刻就是「要拉数据却拉不到」，上报口正好卡在这一刻。
///
/// **网络异常和服务器异常分开**（2026-11-05 产品）：[probe] 只回答手机能不能上网，
/// 查出来不能才弹「网络异常」；手机能上网而后端连不上（后端请求连不上 / 超时、
/// 后端域名解析不了）是服务器异常，只提示一条自动消失的 toast，不弹框。
abstract final class NetworkStatus {
  /// 手机能不能上网。默认实现：后端域名与 [publicHosts] 同时解析，**任一个**解析
  /// 成功就算有网——只看后端域名的话，手机能上网而这个域名 DNS 异常，也会被当成没网。
  /// 飞行模式、Wi-Fi 与蜂窝都关着、连着一个没有外网的 Wi-Fi，全部解析失败。
  ///
  /// 用例在 `test/flutter_test_config.dart` 里统一换成恒为 true，免得真去做 DNS；
  /// 专门验弹窗的用例自己换成 false。
  static NetworkProbe probe = _phoneOnline;

  /// 后端能不能连：解析一次 APP 后端的域名。冷启动 / 回前台、手机有网时用它判断
  /// 要不要提示「服务器异常」。用例同样统一换成恒为 true。
  static NetworkProbe serverProbe = _resolveApiHost;

  /// 判断手机有没有网时一起解析的公共域名（国内外各有可达的），只做 DNS 解析，
  /// 不发请求。
  static const List<String> publicHosts = <String>[
    'www.baidu.com',
    'www.qq.com',
    'www.apple.com',
  ];

  /// 单次解析最多等多久。超时按「解析失败」算：DNS 三秒都答不上来，页面上的请求
  /// 也一样拉不下来。
  static const Duration probeTimeout = Duration(seconds: 3);

  static final StreamController<NetworkFailureSource> _failures =
      StreamController<NetworkFailureSource>.broadcast();

  /// 每次 [reportFailure] 发一个事件，带上失败来自哪边。
  static Stream<NetworkFailureSource> get failures => _failures.stream;

  /// 一次请求因为网络失败了（连不上、超时）。
  ///
  /// `ApiClient` 在重试用尽、抛 `NETWORK_UNREACHABLE` / `NETWORK_TIMEOUT` 前以
  /// [NetworkFailureSource.backend] 调；涂鸦那边的失败由 `FlowerpotState` 统一收口时
  /// 以 [NetworkFailureSource.tuya] 调（涂鸦错误码分不出是不是网络问题，一律交给
  /// [probe] 判断）。
  static void reportFailure([
    NetworkFailureSource source = NetworkFailureSource.tuya,
  ]) {
    if (_failures.hasListener) _failures.add(source);
  }

  static String? get _apiHost {
    try {
      final host = Uri.parse(ApiConfig.baseUrl).host;
      return host.isEmpty ? null : host;
    } on FormatException {
      return null;
    }
  }

  static Future<bool> _phoneOnline() {
    final api = _apiHost;
    final hosts = <String>{
      if (api != null) api,
      ...publicHosts,
    }.toList(growable: false);
    final result = Completer<bool>();
    var pending = hosts.length;
    for (final host in hosts) {
      unawaited(
        _resolves(host).then((ok) {
          pending--;
          if (result.isCompleted) return;
          if (ok) {
            result.complete(true);
          } else if (pending == 0) {
            result.complete(false);
          }
        }),
      );
    }
    return result.future;
  }

  static Future<bool> _resolveApiHost() async {
    final host = _apiHost;
    // API_BASE_URL 配错是构建问题，不拿它来提示。
    if (host == null) return true;
    return _resolves(host, invalidHost: true);
  }

  /// [invalidHost]：域名本身不合法（ArgumentError）时返回什么。
  static Future<bool> _resolves(String host, {bool invalidHost = false}) async {
    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(probeTimeout);
      return addresses.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on ArgumentError {
      return invalidHost;
    }
  }
}
