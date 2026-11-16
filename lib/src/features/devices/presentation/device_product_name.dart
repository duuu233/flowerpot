import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../app/flowerpot_app.dart';

/// 页面文案里称呼设备用涂鸦产品名（2026-11-16）：进页面现问一次这台设备的涂鸦产品名。
///
/// 名字由 [FlowerpotState.productNameLabel] 取（问到前是本次会话上一次问到的，
/// 都没有时说「设备」），问到新的会经 `notifyListeners` 让页面重画。
mixin DeviceProductNameRefresh<T extends StatefulWidget> on State<T> {
  /// 要问产品名的设备；为 null 时不问。
  String? get productNameDeviceId;

  String? _askedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = productNameDeviceId;
    if (id == null || id.isEmpty || id == _askedFor) return;
    _askedFor = id;
    unawaited(FlowerpotScope.of(context).productNameFor(id));
  }
}
