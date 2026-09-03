# 一键 AP 配网的失败释放、取消与手动回落

> 文档类型：Historical Change Record
> 日期：2026-09-03
> 环境：SSH（无 Flutter/Dart 工具链，无 codegraph）
> 分支与起始版本：main / 4860444
> 范围：`lib/src/state.dart`、`lib/src/tuya/tuya_repository.dart`、`lib/src/features/devices/presentation/`（配网页、失败页）、`lib/src/features/devtools/`、`android/.../MainActivity.kt`、`ios/Runner/AppDelegate.swift`、相关测试与文档
> 当前权威文档：[`../../TUYA_SDK_SETUP.md`](../../TUYA_SDK_SETUP.md) 5.3「AP 配网的三步与资源释放」、6.3；[`../../PRD_IMPLEMENTATION.md`](../../PRD_IMPLEMENTATION.md)

## 背景与目标

2026-08-30 的几次提交已经把产品页与联调页改成一键 AP 配网：`pairViaHotspot` 依次取令牌、由 App 连设备热点（`WifiNetworkSpecifier`）、启动 activator，不再让用户分步点「取令牌」「连热点」。本次按文档复核这条链路，重点回答「配网失败会不会把设备/网络占住不释放」，并顺手处理复核中发现的其它问题。

复核结论（修改前）：

1. Android `pairWifi` 只有 activator 回调那两条路径调用 `stopActivator()`。查家庭、取令牌、反射找工厂/枚举、`start()` 抛异常这些在回调注册之前的失败全部不清理，进程仍绑在设备热点上、热点请求不释放；热点随后消失，进程绑着一个已经不在的网络，之后回查设备列表、重试取令牌全部无网失败，直到进程重启。这就是「占用没释放」的根源。
2. Dart `pairViaHotspot` 连上热点后任何一步失败都不调 `leaveDeviceHotspot`；原生 `joinDeviceHotspot` 连上却绑定失败返回 false 时也不释放。
3. 用户在配网期间返回上一页，activator 继续跑满 120 秒、手机继续挂在热点上，`busy` 锁住整个 App，没有任何取消入口；Dart 侧也没有兜底超时，原生不回话就永远锁住。
4. iOS 与 Android 9 及以下 `joinDeviceHotspot` 回 `hotspot_join_unsupported`，产品页没有回落，AP 配网必然失败；iOS `startActivator` 覆盖未回复的 `pairingResult` 会让 Dart 的 Future 永远不完成。
5. 每次都重新取令牌，即使 7 分钟内已有；手动连热点后回来再点必然取不到（没有外网）。
6. `test/widget_test.dart` 端到端用例、`pairing_failure_page_test.dart` 的副标题断言还是旧流程；`TUYA_SDK_SETUP.md` 5.3/6.3 与 `AI_CONTEXT.md`、`PRD_IMPLEMENTATION.md`、`PROJECT_STRUCTURE.md` 仍描述两步 AP 与 EZ 切换。

## 变更内容

契约：

- `TuyaRepository` 增加 `cancelPairing()`；`MethodChannelTuyaRepository` 透传，Mock 为空操作。`leaveDeviceHotspot` 文档补充「失败后必须调、无连接时安全」。

状态层 `FlowerpotState`：

- `pairViaHotspot` 重写：令牌 7 分钟内复用不再取；连热点只对 `hotspot_join_unsupported` 回落——先 `scanWifi` 看手机是否已在设备热点上，是就直接配，否则以 `hotspot_manual_required` 返回并保留令牌；新增 `hotspotJoinedManually` 参数，第二次点击跳过检查直接配。任何失败（`TuyaException` / `ApiException` / 其它）都经 `_abandonPairingAttempt`：发出过连热点就 `leaveDeviceHotspot`，发出过配网就作废本地令牌时间。三步耗时仍拼进结果文案。
- 连热点 90 秒、配网 150 秒的 Dart 侧兜底超时；配网超时先 `cancelPairing` 再以 `pair_timeout` 失败。`pair_cancelled` / `pair_timeout` 不再做失败后的三轮云端回查。
- 新增 `cancelPairing()`（走 `_run` 不走 `_guard`，配网占锁时也能调）。删除无调用方的公开 `joinDeviceHotspot`。

页面：

- `PairingPage`：收到 `hotspot_manual_required` 不跳失败页，提示卡换成去系统设置连热点的引导，按钮变「已连接热点，开始配网」；配网期间页面 `dispose` 调用 `cancelPairing`（发起时留下 `FlowerpotState` 引用，`dispose` 里不能查 InheritedWidget）。去掉 `build` 里未使用的 `scan` 变量。
- `PairingFailurePage`：`hintFor(code)` 把 `hotspot_join_cancelled/failed/timeout`、`hotspot_bind_failed`、`pair_cancelled`、`pair_timeout`、`1006` 换成一句可操作的话，原始码附括号；其余照常显示带标签与耗时的原文。
- 联调页：说明文案更新；新增「热点已手动连上，开始配网」与「取消配网」（后者不受操作锁禁用）。

Android `MainActivity.kt`：

- 新增 `PairingResult` 回复包装：`pairWifiDevice` 的成功、失败、异常回复之前一律 `stopActivator()`（停 activator、解除进程绑定、注销热点请求）。`pairingResult` 字段记录进行中的调用。
- 新增 `releasePairing(code, message)`：停掉一切并把错误回给进行中的 `pairWifiDevice`；`cancelPairing` 与 `leaveDeviceHotspot` 都走它，且放在 `ensureReady` 之前（SDK 没起来也能释放）；`onDestroy` 也调用；`pairWifi` 发现上一次未回复就先了结它。
- `joinDeviceHotspot`：发起前 `unbindProcessNetwork()` 整个清掉残留；连上但绑定失败回 `hotspot_bind_failed` 并立即释放；`onUnavailable` 注销回调。`prepareActivatorToken` 发现没有配网在跑却还绑着网络时先解绑。

iOS `AppDelegate.swift`：

- `joinDeviceHotspot` 改为 `NEHotspotConfigurationManager`（`joinOnce`，精确 SSID 或 iOS 13 前缀）；`alreadyAssociated` 视为成功，`userDenied` 回 `hotspot_join_cancelled`，其它错误（含缺 entitlement）回 `hotspot_join_unsupported` 让 Dart 走手动路径。`leaveDeviceHotspot` 删除临时配置。
- 新增 `cancelPairing` 与 `finishPairing`：停 `stopConfigWiFi`、把 `pair_cancelled` 回给挂着的 `pairingResult`；`startActivator` 先了结上一次再覆盖。

测试与文档：

- 新增 `test/state_pairing_test.dart`：失败释放与作废令牌、拒绝连热点保留令牌并复用、手动回落两次点击、已在热点上直接配、取消不回查、原生不回话超时中止、配网占锁时可取消。
- `pairing_page_test.dart` 新增手动路径、拒绝连热点跳失败页并释放、退出页面取消三个用例；`widget_test.dart` 端到端改为一次点击；`pairing_failure_page_test.dart` 修正副标题断言并新增已知码提示用例。
- `TUYA_SDK_SETUP.md` 5.3 子节改写为「AP 配网的三步与资源释放」、6.3 改写；`AI_CONTEXT.md` 第 5、9 节、`PRD_IMPLEMENTATION.md`、`PROJECT_STRUCTURE.md`、`docs/README.md` 与本索引同步。

## 关键决策

- **释放放在回复包装里，而不是逐条失败路径补调用**。失败路径太多，逐一补迟早漏；包装保证「只要回了话就放了资源」。
- **`hotspot_join_unsupported` 是回落不是失败**，令牌保留、不释放任何东西；其它连热点失败（取消、不存在、超时、绑定失败）照常失败并释放。
- **令牌只在配网真正发出去之后才作废**：连热点阶段失败令牌没用过，重试直接复用，也避免手动路径在无外网时再去取。
- **取消与超时不做云端回查**：设备不可能在这两种情况下刚好配上，省掉六秒空等。
- **iOS 只写代码不加 entitlement**：`Runner.entitlements` 不存在且需在开发者后台开启 Hotspot Configuration，贸然加会让现有描述文件签不过；未配置时链路自动回落到手动路径。

## 外部操作

无。未改动密钥、安全组件、签名材料与平台配置。

## 验证结果

- 本机（SSH 环境）没有 Flutter/Dart 工具链，`codegraph` 也不存在，内网 nas 连接超时：`dart format`、`flutter analyze`、`flutter test`、Android/iOS 编译**均未运行**，只做了人工逐段复核（括号配对、类型、`FutureOr` 回调、Kotlin inner class 可见性、Swift 可选枚举模式匹配）。
- 未做真机验证。

## 未完成项与风险

- 必须在带工具链的机器上补跑 `dart format lib test`、`flutter analyze lib test`、`flutter test`（重点：`test/state_pairing_test.dart` 全部用假时钟推进，`Future.timeout` 的计时器在配网完成时取消，若出现 pending timer 报错优先检查 `_HangingRepository` 的取消路径）、Android 构建与 iOS Xcode 编译。
- `NEHotspotConfigurationError` 在缺 entitlement 时的具体错误码未实测，代码把 `userDenied` 之外的所有错误都当作「不支持」回落，保守但不会卡死。
- Android 真机需验证：配网失败后立刻重试能取到令牌（说明绑定已释放）、配网期间按返回后手机回到路由器、`onDestroy` 释放。
- 热点识别前缀是否覆盖量产 SSID 仍未确认。

## 回滚或恢复

Dart、原生、测试与文档改动集中在上列文件，`git checkout -- <paths>` 回到 4860444 即可；无数据迁移与平台配置变更。
