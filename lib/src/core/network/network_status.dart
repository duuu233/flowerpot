import 'dart:async';
import 'dart:io' show InternetAddress, SocketException;

import 'api_config.dart';

/// 判断手机当前能不能上网；true = 能。
typedef NetworkProbe = Future<bool> Function();

/// 「手机现在有没有网」的判断，以及「请求因为网络失败了」的全局上报口。
///
/// 「网络异常」弹窗（`NetworkAlertHost`）只在两种时机问一次 [probe]：冷启动 /
/// 回前台，以及这里收到一次 [reportFailure] 之后。**不常驻监听系统网络变化**——
/// 那要接 `connectivity_plus` 或原生桥接，本机没有 Flutter / Kotlin 工具链验证不了；
/// 用户真正受影响的时刻就是「要拉数据却拉不到」，上报口正好卡在这一刻。
///
/// 上报只是「去查一次」的信号，弹不弹由 [probe] 决定：设备离线、后端业务报错
/// 这类失败查出来网是通的，什么都不会发生。
abstract final class NetworkStatus {
  /// 默认实现：解析一次 APP 后端的域名。飞行模式、Wi-Fi 与蜂窝都关着、连着一个
  /// 没有外网的 Wi-Fi，都会解析失败。
  ///
  /// 用例在 `test/flutter_test_config.dart` 里统一换成恒为 true，免得真去做 DNS；
  /// 专门验弹窗的用例自己换成 false。
  static NetworkProbe probe = _resolveApiHost;

  /// 单次探测最多等多久。超时按「没网」算：DNS 三秒都答不上来，页面上的请求也
  /// 一样拉不下来。
  static const Duration probeTimeout = Duration(seconds: 3);

  static final StreamController<void> _failures =
      StreamController<void>.broadcast();

  /// 每次 [reportFailure] 发一个事件。
  static Stream<void> get failures => _failures.stream;

  /// 一次请求因为网络失败了（连不上、超时）。
  ///
  /// `ApiClient` 在重试用尽、抛 `NETWORK_UNREACHABLE` / `NETWORK_TIMEOUT` 前调；
  /// 涂鸦那边的失败由 `FlowerpotState` 统一收口时调（涂鸦错误码分不出是不是网络
  /// 问题，一律交给 [probe] 判断）。
  static void reportFailure() {
    if (_failures.hasListener) _failures.add(null);
  }

  static Future<bool> _resolveApiHost() async {
    try {
      final host = Uri.parse(ApiConfig.baseUrl).host;
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(probeTimeout);
      return addresses.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on ArgumentError {
      // API_BASE_URL 配错是构建问题，不是手机没网，不拿它来弹窗。
      return true;
    }
  }
}
