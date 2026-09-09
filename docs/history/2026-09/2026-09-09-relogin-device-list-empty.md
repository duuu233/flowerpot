# 重新登录后读不到已绑定设备

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：SSH
> 分支与起始版本：main / b162068
> 范围：`lib/src/state.dart`、设备列表页、Android / iOS 桥接的家庭选择
> 当前权威文档：`AI_CONTEXT.md`、`docs/TUYA_SDK_SETUP.md`

## 背景与目标

反馈：重新登录之后读不到已经绑定的设备，设备列表是空的。

## 排查

设备清单只有一条来源：`FlowerpotState._refreshDevicesForSession` → `TuyaRepository.getDevices()` → 原生 `getDevices` → `withHome` 查家庭 → `getHomeDetail` 取设备。页面 `DeviceListPage` 直接画 `state.devices`，不与后端交叉过滤。顺着这条链读下来，有两处**确定的缺陷**能让「设备读不出来」变成「界面显示没有设备」：

1. **失败被吞掉，且和空账号长得一模一样。** 登录、注册、`initialize()` 恢复会话都调用 `_refreshDevicesForSession(ignoreErrors: true)`，`catch (_)` 什么都不做。家庭查询失败、网络抖动、SDK 报错之后，`_devices` 保持为空，列表页画的是「暂无设备」——用户看到的就是设备全没了，也没有任何可操作的反馈。下拉刷新原来接的是 `state.refreshDevices`，它会把异常抛回 `RefreshIndicator.onRefresh`，只进日志，界面上同样毫无反应。
2. **家庭选择不稳定。** 两端桥接都是 `queryHomeList` / `getHomeList` 之后取**第一个**家庭（Android `homes.filterNotNull().firstOrNull()`、iOS `homes?.first`）。这个顺序在两次登录之间并不保证一致，账号名下只要有两个家庭，就可能这次登录读到 A 家的设备、下次读到 B 家的 0 台。而第二个家庭恰恰是这套代码自己会造出来的：`queryHomeList` 返回空时会自动建一个「我的花园」，一次瞬时的空返回就会给账号留下一个永久的空家庭。

真正的触发点还需要现场确认（见「未完成项」），但上面两条无论如何都要修：第 1 条让故障看起来像数据丢失，第 2 条会让同一个账号在不同登录之间看到不同的设备。

## 变更内容

- `FlowerpotState` 新增 `deviceLoadError`：`_refreshDevicesForSession` 成功清空、失败记录（涂鸦 / 接口 / 未知三类错误都带上来源和错误码），失败时**不清空已有列表**。
- `probeDevices()` 改名为 `reloadDevices()`，成为设备列表页下拉刷新、错误页「重试」和联调页共用的入口——失败作为 `ActionResult` 返回，不再抛进 `RefreshIndicator`。调用方从原来的 `state.refreshDevices` 换成它，失败弹统一提示条。
- `DeviceListPage`：列表为空**且**有 `deviceLoadError` 时，画 `_DeviceListError`（`AppErrorView` + 「重试」，外面套 `ListView` 保持可下拉），不再画「暂无设备」。
- Android `withHome`：新增 `pickHome`，先挑带设备的家庭、同样带设备时取 `homeId` 最小的那个，并把选中的家庭和家庭总数写进日志。iOS `withHome`：家庭列表按 `homeId` 升序后再取第一个。两端都从「取返回顺序的第一个」变成稳定规则。

## 关键决策

- 没有动「查不到家庭就自动建家」这条逻辑：新账号确实需要它。但把选择规则钉稳之后，即使多出一个空家庭，也不会再出现「这次登录看得到、下次看不到」的摆动。
- 失败时保留上一次的设备列表，而不是清空：断网重进时留着上次的快照比白屏好，且错误态只在列表为空时才盖上来。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK**，`flutter analyze` 与 `flutter test` 均未执行；Android / iOS 桥接的改动同样**没有编译过**（本机没有 Android SDK 与 Xcode）。
- 新增用例（未运行）：`test/features/devices/device_list_page_test.dart` —— `getDevices` 抛错后 `deviceLoadError` 带上错误码、列表页显示错误态与「重试」而不是「暂无设备」，仓库恢复后点「重试」列表回到正常。

## 追加：把现场信息搬到真实页面上（同日）

维护者反馈已经基本不用联调页，需要在正常使用的页面上就能看到关键信息。补充：

- `FlowerpotState` 记录 `lastHomeId`（每次成功读设备后从原生 `currentHomeId` 读回，原生此时已缓存，不会再触发一次云端查询），并提供 `sessionDiagnostics`：`uid … · 家庭 … · 设备 N 台 · 失败原因`。
- 设备列表页的**错误态和「暂无设备」空态**都在底部画这一行（`Key('device-list-diagnostics')`，`SelectableText` 可长按复制）。「一台都没有」时最需要知道的就是查的哪个家庭、哪个账号。
- 每次读设备列表都打一行 `[devices] uid … · 家庭 … · 设备 N 台 …`（`debugPrint`，不按 debug 模式过滤，`adb logcat -s flutter` / Xcode 控制台可见）。
- iOS 侧补一行 `[flowerpot] home picked <id> of <n> homes`，与 Android 的 `home picked` 日志对齐。

### 家庭 id 从哪来，和 Wi-Fi 有没有关系

家庭属于**涂鸦账号**，存在云端，由 `queryHomeList` / `getHomeList` 按当前登录的 uid 拉取，桥接把选中的 id 缓存在 `homeId` / `currentHome`（退登时清空）。手机连哪个 Wi-Fi **不参与选家庭**，所以「换了 Wi-Fi 家庭就变了」这条不成立。

但网络状态确实会间接影响，两条路径：

1. **AP 配网期间手机挂在设备热点上，没有外网。** 此时若家庭尚未缓存（例如刚启动就直接进配网），`withHome` 会在无网状态下查家庭：要么直接失败，要么拿到一份空的本地缓存——而空列表会走「自动建家」。这正是账号里多出一个空家庭的来路。取令牌本身已经特意安排在连热点之前完成（`prepareActivatorToken`），但 `pairWifiDevice` 在没有新鲜令牌时仍会回落到「查家庭 + 取令牌」。
2. **配网时用的是哪个家庭，设备就绑进哪个家庭**（`fetchActivatorToken(homeId)`）。一旦有两个家庭，配网落在 A、列表读到 B，就是「设备读不到」。

所以真正的因果是「多个家庭 + 选择不稳定」，Wi-Fi 只是制造出第二个家庭的诱因之一。

## 未完成项与风险

- **根因未确认。** 请在复现的那台手机上用联调页（登录页「涂鸦 SDK 联调」或「我的」标题栏图标）跑一次「拉取设备列表」，它现在会回报「共 N 台（家庭 X）」。把这个家庭 id 和配网成功那次的家庭 id 对比：
  - 两次家庭 id 不同 → 就是上面第 2 条，账号下有多个家庭，本次改动应当能消除摆动；
  - 家庭 id 相同但设备是 0 台 → 家庭对但设备不在里面，问题在配网落到了别的账号/家庭，或云端已解绑；
  - 拉取直接报错 → 现在错误码会显示在联调页和设备列表页上，按错误码继续查。
- 若同一手机号在 APP 后端换过 `userNo`（涂鸦 uid 来自后端 `userNo` + `tuYaPwd`），重新登录等于登进另一个涂鸦账号，设备自然一台都没有。这一条只能在后端核对，客户端看不出来，联调页显示的 uid 可以作为对照。
- Android 的 `pickHome` 依赖 `HomeBean.getDeviceList()`；该字段在部分 SDK 版本里由 `queryHomeList` 返回时为空，此时退化为「取 homeId 最小」，仍然是稳定的。
