# 2026-09-10（晚）按设备方流程把「手机连接设备热点」这一步加回配网

## 背景

设备方给出配网流程，并要求核对项目是否按此实现：

> **配网模式**：设备采用涂鸦标准 AP 热点配网（AP-cfg），没使用 EZ/SmartConfig 快连。
> **配网流程**：未激活设备开机后自动开启 Wi-Fi 热点（热点名 `smartlife_xxx` /
> `tuya_mdev_xxx`）→ **手机连接该热点** → 打开涂鸦 App → App 通过热点下发目标路由器
> SSID/密码 → 设备自动切换连网并连云激活。
> 目前那个版本是开机即初始化 WiFi，未激活则 SDK 自动开 AP 热点 ⇒ **开机即可配网**。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `816f512`。

## 核对结论：**不一致，缺了第 2 步**

逐条对照：

| 设备方流程 | 项目现状（改之前） |
| --- | --- |
| 设备开机自动开热点 `smartlife_xxx` / `tuya_mdev_xxx` | ✅ 两个前缀都在 `isDeviceHotspotName` 白名单里，搜索页据此认设备 |
| **手机连接该热点** | ❌ **没有这一步** |
| App 通过热点下发 SSID/密码 | ✅ `apStartPairing` → `startActivator` |
| 设备切网并连云激活 | ✅ 设备侧 |
| 开机即可配网、无需额外操作 | ✅ 端上文案一律只说「请确认设备已开机」 |

第 2 步是 2026-09-10 白天被**整个去掉**的。当时的依据是官方文档那句：

> 在配网过程中，SDK 会在指定时间内自动去连接 AP 热点

据此赌 `startActivator` 自己会连热点，于是把原来在搜索页调的 `connectDeviceForPairing()`
（会连热点但也会卡到超时）删掉，没有在别处补上。

**这个赌已经被证伪。** 测试反馈配网失败，提示
「设备未能成功连接到当前WIFI网络，out of time」。关键不在「超时」，而在**没有任何
207xxx 失败码**：涂鸦新流程的 207209/207210/207211/207212/207213 全部是
「设备**收到配网信息之后**」的错误（配网信息错误、找不到路由器、密码错误、连接路由器
失败、DHCP 失败）。一个都没出现，说明设备从头到尾**没收到过任何东西**——通道压根没
建起来。这与「手机从未连上设备热点」完全吻合，也与设备方把「手机连接该热点」单列为
一步相符。

## 改动

### `lib/src/state.dart`

`pairViaDeviceHotspot` 改为两步，顺序照设备方流程：

```dart
_setPairingStage(PairingStage.connectingDevice);
final target = hotspotSsid ?? _wifiScan?.deviceHotspots...firstOrNull;
await _joinHotspotForPairing(target: target, joinedManually: false);  // ← 加回来的第 2 步
_setPairingStage(PairingStage.sendingWifi);
await _repository.apStartPairing(ssid: ssid, password: password, timeout: timeout);
```

- 新增 `hotspotSsid` 参数。
- 失败时按原流程同样的规则清理：`_abandonPairingAttempt(releaseHotspot:, invalidateToken:)`
  ——连上了就要释放，凭据发出去了令牌就可能已被设备用掉、要作废；
  `hotspot_manual_required`（平台不让 App 连热点，需用户去系统设置）不算失败，什么都不放。
- `_joinHotspotForPairing` 是原流程就有的方法，没有改动：已经连在目标热点上时直接跳过
  （不白弹授权框）、Android 用确切 SSID、iOS 退到前缀匹配、有 90 秒上限、
  平台不支持时抛 `hotspot_manual_required` 引导用户手动连。

**为什么放在配网这一步而不是搜索页**：一连上设备热点手机就没有外网，而取令牌
（`getActivatorToken`）和取安全配置（`getDeviceSecurityConfigs`）都要走云端。那两件事
已由搜索页的 `prepareForPairing` 在**还连着路由器**时预取完，到这一步只剩纯本地通信。
这也是白天那次卡死的教训：连热点提前到搜索页，会把后面所有云端调用一起拖下水。

### `lib/src/features/devices/presentation/pairing_page.dart`

`_pair()` 把 `widget.arguments?.hotspotSsid` 传下去——Android 原生拒绝只给前缀
（`hotspot_ssid_required`），必须带确切热点名；搜索页扫到设备时已经把它放进
`PairingArguments` 了。注释同步改掉「连热点由 SDK 自己完成」那段。

### `test/state_pairing_test.dart`

更新新流程那条测试的注释与用例名（原注释写着「连热点由 SDK 完成、没有系统授权框」，
已不成立）。**断言未改也无需改**：用例没传 `hotspotSsid`、`_wifiScan` 为空 ⇒ `target`
为 null ⇒ 走前缀那一支 ⇒ `MockTuyaRepository.joinDeviceHotspot` 返回 true ⇒ 配网照常成功。

## 代价与取舍

Android 10+ 上 `WifiNetworkSpecifier` + `requestNetwork` 会弹一次系统入网授权框，
**关不掉也不能替用户点**（这一条 2026-09-10 已向涂鸦求证并实测确认）。但：

- 它只在用户**已经点了「开始配网」之后**出现，是流程里预期的一步，不再像以前那样在
  搜索页上莫名弹出；
- 手机已经连在该热点上时（上次配网留下的、或用户自己连的）直接跳过，不白弹；
- **能配网成功 > 没有弹框。** 不弹框但配不上，对用户毫无价值。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。静态自检：

- `state.dart` / `pairing_page.dart` 括号配平：与改动前同基线对比，增量 `(` +9 / `)` +9、
  `{` +3 / `}` +3，配平（该文件在 HEAD 上本来就有 1 个 `(` 的计数偏差，来自多行字符串，
  是检查脚本的已知假阳性）。
- 逐条核对现有测试断言不会被打破（见上）。

## 遗留

- **下一次失败的判读方式变了。** 现在通道会真的建起来，所以：
  - 出现 `207xxx` ⇒ 通道已通，失败在设备侧，按码直接定位（密码 / 路由器 / DHCP / 连云）；
  - 出现 `hotspot_join_*` ⇒ 连热点这一步本身没成（用户取消了授权框、热点不在了、超时）；
  - 仍是 `out of time` 且无码 ⇒ 热点连上了但 `startActivator` 还是没能和设备说上话，
    那就要怀疑 `newOptimizedActivator` 这条新流程 API 本身，改回原流程的
    `pairWifiDevice`（`ActivatorModelEnum.TY_AP`，即 `pairViaHotspot`，代码都还在）。
- 失败码现在一定看得见（`816f512` 已修），请把括号里的码带回来。

## 回滚

`git revert` 本次提交。改动为 2 个 Dart 文件 + 1 个测试注释，无原生与数据改动。
