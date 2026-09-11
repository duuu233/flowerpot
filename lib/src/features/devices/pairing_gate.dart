/// 配网模式总闸。
///
/// **2026-09-11 产品要求：先把 AP（热点）配网整条屏蔽掉，只走蓝牙双模。**
/// 目的是在真机上确认**设备端到底支不支持**蓝牙配网——不支持就由设备方去改固件。
/// 留着 AP 那条并行的话，用户一旦落到它上面就配成了，反而验不出蓝牙这条的结论。
///
/// ⚠️ **这是门禁，不是删除。** AP 那整条（`pairViaHotspot` / `connectDeviceHotspot` /
/// `_joinHotspotForPairing` / 原生 `joinDeviceHotspot` / 失败页的「改用热点方式」/
/// 搜索页的 Wi-Fi 热点列表与真扫节奏）代码**原样留着**，[apEnabled] 翻回 `true`
/// 就全部回来，不需要再写一遍。
abstract final class PairingGate {
  /// AP（热点）配网是否可用。
  ///
  /// `false` 时全部入口一起关掉：搜索页不列热点、不发主动 Wi-Fi 扫描（不再烧那条
  /// 2 分钟 4 次的配额）、失败页不给「改用热点方式」、配网页拿不到 BLE uuid 时
  /// **直接报错而不是悄悄退回 AP**——悄悄退回会让「蓝牙不通」被一次 AP 成功盖掉，
  /// 正好毁掉这轮要验的东西。
  /// ⚠️ **不是 `const`**：用例要两头都跑得起来——AP 关着时验这一轮的行为，
  /// 翻开时验回落那条**代码仍然完好**（那才是「屏蔽不是删除」的意义）。
  /// 生产值就是下面这个；用例改了必须在 `tearDown` 里 [reset] 回来。
  static bool apEnabled = _apEnabledDefault;

  /// 蓝牙搜索结果**不做任何过滤**，扫到什么就画什么。
  ///
  /// 正常动线只该列「没绑过的涂鸦单点设备」。但这一轮要回答的是**「设备到底在不在
  /// 广播、广播成什么样」**，被过滤掉的恰恰可能就是答案：绑过的、别的 ScanType 的、
  /// 甚至 uuid 为空的，都要让人看见。
  ///
  /// 影响两处：Dart 侧不再剔除 `bound` 的设备；原生侧把 `LeScanSetting` 的
  /// ScanType 从只加 `SINGLE` 改成**全部加上**。
  static bool showUnfilteredBleScan = _showUnfilteredBleScanDefault;

  static const bool _apEnabledDefault = false;
  static const bool _showUnfilteredBleScanDefault = true;

  /// 用例收尾用：把两个开关恢复成生产值。
  static void reset() {
    apEnabled = _apEnabledDefault;
    showUnfilteredBleScan = _showUnfilteredBleScanDefault;
  }
}
