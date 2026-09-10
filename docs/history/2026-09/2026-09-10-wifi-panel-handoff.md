# 2026-09-10（晚）改由用户在系统 Wi-Fi 面板连设备热点（不要授权框）

## 决定

实测证明 SDK 不会替我们连设备热点（见
`2026-09-10-ap-connect-must-precede-sdk.md`），而 Android 10+ 下首次连接只有两条路：
App 发起 `WifiNetworkSpecifier`（**必弹**系统入网授权框）或用户自己连。
**产品选了后者**：不要那个框。

旁证：测试反馈智能生活 App 在 AP 模式下配网能成功、且不弹授权框——它的 AP 流程里本来
就有「去连接」那一步，跳系统 Wi-Fi 让用户选 `SmartLife_xxxx` 再回来。我们现在做的是
同一条路，只是把整页设置换成浮在 App 之上的 Wi-Fi 面板。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `92366e3`。

## 改动

### 原生 `MainActivity.kt`

新增 `openWifiPanel`：Android 10+ 用 `Settings.Panel.ACTION_INTERNET_CONNECTIVITY`
——**浮在当前应用之上的底部面板**，用户点一下热点就连上、不用离开 App；低版本退回
`Settings.ACTION_WIFI_SETTINGS`。不加 `FLAG_ACTIVITY_NEW_TASK`（加了会变成独立页面，
用户得手动返回）。不在原生等结果，连上与否由 Dart 轮询判断。

顺带的好处：这样连上的网络会被**系统保存**，同一台设备下次可能自动重连、第二次配网
完全无感——`WifiNetworkSpecifier` 做不到（它建立的是进程专属的一次性连接，不进
「已保存的网络」，所以每次都要弹框）。

### `lib/src/tuya/tuya_repository.dart` / `lib/src/state.dart`

- 抽象与实现都加 `openWifiPanel()`。
- `FlowerpotState`：`onDeviceHotspot`（读缓存判断当前是否已在设备热点上，不占扫描配额）、
  `refreshOnDeviceHotspot()`（轮询用）、`openWifiPanel()`。

### `lib/src/features/devices/presentation/pairing_page.dart`

`_pair()` 拆成「前置 + 配网」：

```
_pair()
 ├ 校验输入
 ├ Android 且不在设备热点上 ⇒ 存下凭据、进引导态、拉起 Wi-Fi 面板、每秒轮询
 │    连上后 _hotspotPoll 自动调 _startPairing，用户不用回来再点一次
 └ 否则直接 _startPairing()
```

- 引导态下底部换成 `_HotspotHandoffBar`：一行说明（写明要点哪个热点名 + 当前连的是
  什么）+ 「打开系统 Wi-Fi 列表」按钮。**不用弹层**——产品口径是不要弹框，说明画在页面上。
- iOS 不走这条（`_needsHotspotHandoff` 只在 Android 为真）：iOS 靠
  `NEHotspotConfiguration(ssidPrefix:)` 按前缀连，且没有可拉起的 Wi-Fi 面板，保持原行为。
- **修了一个会咬人的细节**：`didChangeAppLifecycleState` 在引导态下不再刷新 SSID。
  用户从 Wi-Fi 面板回来时 `resumed` 会触发 `_applyCurrentSsid`，而那时手机正挂在设备
  热点上、按「没连 Wi-Fi」处理 ⇒ 会把用户填好的路由器名**清空**。配网本身不受影响
  （凭据在发起前已存进 `_pendingRequest`），但界面看起来像白填了一遍。

## 测试改动（行为变了，断言必须跟着变）

- `MockTuyaRepository`：新增可变的 `currentSsid`（默认 `TP-LINK_2.4G`，`scanWifi` 用它）
  与 `wifiPanelOpens` 计数，用例据此模拟「用户已在系统 Wi-Fi 面板连上设备热点」。
- `pairing_page_test.dart`：新增 `_connectDeviceHotspot()` 辅助（断言引导态出现 + 面板
  被拉起过，然后翻 `currentSsid` 并推进 1 秒让轮询续跑），插进 4 处点「开始配网」的用例；
  `_FailingRepository()` 提成变量以便翻标志。
- **`a refused hotspot join opens the failure page` 整条改写**：它覆写的是
  `joinDeviceHotspot`，而新流程根本不调它——这条用例从 `b3d0d09` 起就已经测不到东西。
  换成新现实下的等价断言：*用户没连上就一直停在引导态、绝不把凭据发出去，连上后自动
  续跑*（同时断言 `wifiPanelOpens == 1`、`pairCalls` 从 0 变 1）。随之删掉已无用的
  `_RefusedHotspotRepository`。
- `widget_test.dart`：`_pumpApp` 改为返回它创建的 `MockTuyaRepository`，配网那条用例据此
  模拟连上热点。
- `state_pairing_test.dart` **不动**：那里的 `joinDeviceHotspot` / `leaveCalls` 测的是
  legacy `pairViaHotspot`，该方法仍然存在，用例依然有效。

## 验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链。静态自检：

- 5 个产品文件 + 3 个测试文件括号配平，与 HEAD 同基线。
- 检查过 `TuyaRepository` 的实现只有 `MethodChannelTuyaRepository` 与
  `MockTuyaRepository`（其余测试替身都继承后者），新方法两边都有。
- 修掉了一次脚本替换留下的孤立 `@override`（落在 `currentSsid` 字段上，会编译失败）。
- ⚠️ `widget_test.dart` 里 `expect(find.byKey(const Key('pairing-hotspot-step')), findsOneWidget)`
  与 `pairing_page_test.dart` 的 `findsNothing` 互相矛盾，**这是本次改动之前就存在的**
  （该步骤 2026-09-10 按产品要求删掉了），没有一并动它。

## 遗留

- 真机复测：面板是否以底部弹层出现、连上后是否自动续跑、第二次配网是否因系统保存了
  热点而无感。
- 换设备时 SSID 不同，仍要再走一次引导。
