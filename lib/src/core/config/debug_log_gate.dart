/// 联调日志的总闸。
///
/// **2026-09-19 用户要求：暂时屏蔽调试日志功能，代码不要删。**
/// **2026-09-23 重新打开**：开始割草机与设备联调，「可以显示调试日志了，和以前一样有 DPID
/// 的都打印进去」。发给别人看的包再翻回 `false`。
///
/// 联调日志（左下角那颗药丸 + 展开的日志框）是 2026-09-12 为真机联调加的临时设施：
/// 产品不看 logcat，要的是「能截图的日志」。现在要给别人看包了，它不该出现在界面上。
///
/// ⚠️ **这是门禁，不是删除**：[interactionLog] 翻回 `true`，浮层、面板、
/// `FlowerpotState.interactionLog` 那一整套原样回来，一行代码都不用补。
///
/// ⚠️ **关掉之后割草机那套 DP 日志也看不到了**（2026-09-18 接的 DP 下发/上报走的就是
/// 这同一个日志框）。要联调割草机功能点时，把这个开关翻回 `true`。
abstract final class DebugLogGate {
  /// 联调日志开不开。
  ///
  /// 关着时：[FlowerpotState._logInteraction] 直接返回（不记录、不通知），
  /// `InteractionLogOverlay` 也不挂浮层——两头都断，省得只藏了界面、日志还在后台攒。
  ///
  /// ⚠️ **不是 `const`**：用例要能两头都验（关着时不画、翻开时照常记录）。
  /// 用例改过必须在 `tearDown` 里 [reset] 回来。
  static bool interactionLog = _interactionLogDefault;

  /// 生产值。2026-09-19 关闭，2026-09-23 联调重新打开。
  static const bool _interactionLogDefault = true;

  /// 用例收尾用：恢复成生产值。
  static void reset() => interactionLog = _interactionLogDefault;
}
