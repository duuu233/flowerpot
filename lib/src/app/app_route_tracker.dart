import 'package:flutter/widgets.dart';

/// 根 Navigator 的路由栈。
///
/// 全局弹窗靠它知道：现在是哪一页（配网动线上不弹「网络异常」、只有设备页才弹固件升级
/// 提醒、「重试」刷新哪一页），以及最上面是不是正盖着别的弹框。挂在 `FlowerpotApp` 的
/// `navigatorObservers` 上。
class AppRouteTracker extends NavigatorObserver {
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];
  final List<VoidCallback> _listeners = <VoidCallback>[];

  /// 路由栈一变就回调。回调发生在 Navigator 刷新路由栈的过程中，**不能当场推路由**。
  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// 最上面那一「页」；对话框、底部弹层、进度圈不算页。
  Route<dynamic>? get currentPage {
    for (final route in _routes.reversed) {
      if (route is PageRoute) return route;
    }
    return null;
  }

  /// 最上面正盖着对话框 / 底部弹层 / 进度圈。
  bool get popupOnTop => _routes.isNotEmpty && _routes.last is! PageRoute;

  void _changed() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // didReplace 与 didRemove 谁先到不作假设：两边都按「在不在栈里」幂等处理。
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute != null && !_routes.contains(newRoute)) {
      if (index >= 0) {
        _routes[index] = newRoute;
      } else {
        _routes.add(newRoute);
      }
    } else if (index >= 0) {
      _routes.removeAt(index);
    }
    _changed();
  }
}
