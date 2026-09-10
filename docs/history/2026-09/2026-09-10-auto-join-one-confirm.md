# 2026-09-10（晚，定稿）连热点改回「自动选中 + 一次确认」

## 产品反馈

> 还是不对啊，为什么要在 wifi 列表中选择一下设备，不可以自动吗？
> 前面搜索设备已经搜索出来了，就按这个设备进行下一步不行吗？

以及 iOS 侧的实测对照：

> 我刚尝试了下 iOS 端的智能设备，他是选择了一下 WIFI，**是 WIFI 不是设备**，
> 然后输入了 wifi 密码就去配网连接了。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `8d00c29`。

## 产品说得对，我上一版选错了

上一版（`da5a054`）为了彻底消掉系统框，改成**拉起系统 Wi-Fi 面板让用户自己在列表里找
`smartlife_xxxx`**。这确实多余：搜索页已经拿到了确切热点名，没有理由让用户再挑一遍。

但有一条事实绕不过去，必须写死，免得以后再来回：

- **「搜到」和「能连上」是两件事。** 搜索页用 `WifiManager.getScanResults()` 只能**看见**
  热点名（读权限）；要让手机**真的连上**，Android 10+ 只有 `WifiNetworkSpecifier` +
  `requestNetwork` 一条公开 API，**必然弹一次系统确认框**，关不掉、不能代点
  （`addNetwork`/`enableNetwork` 对 targetSdk ≥ 29 的应用 always fail）。
- 涂鸦 SDK 也一样没有特权（实测 `queryDeviceConfigState` 跑满 45 秒报 `207220`、
  全程无框、手机始终在路由器上）。

⇒ **「零确认」做不到；「自动选中」做得到。** 两者只差一次点击，而自动选中比"打开面板 →
列表里找 → 点 → 返回"少好几步，且全程不离开 App。产品选了自动选中。

iOS 的对照正好印证整体动线：**用户选的是路由器 Wi-Fi，不是设备**；连设备热点那一步由
App 自己做（iOS 用 `NEHotspotConfiguration(ssidPrefix:)`，系统同样只弹一次）。
我们的动线本来就是这样——搜索页自动带走设备，「连接 Wi-Fi」页只问路由器 SSID + 密码。

## 改动

### `lib/src/state.dart` — `pairViaDeviceHotspot` 恢复为三步

```
connectingDevice: ① _joinHotspotForPairing(确切 SSID)   手机连设备热点（已连则跳过）
                  ② apQueryDeviceWifi(45s)              建通道 + 查设备状态（列表不展示）
sendingWifi:      ③ apStartPairing(120s)                下发路由器凭据
connectingCloud:  由 onStep 驱动；一条都没报时才用 1–2s 兜底
```

- 类注释重写：三步表格 + 「为什么①必须由我们做」（实测证据）+ 产品口径（自动选中、
  一次确认、已连则零点击）+ 前缀/确切 SSID 的平台差异。
- 失败收尾 `_releaseDeviceHotspotPairing` 改为**两样都放**：`apStopPairing`（SDK 配网器）
  **和** `leaveDeviceHotspot`（我们自己的进程网络绑定）。少放哪一样，下次配网都起不来——
  绑着一个没有外网的网络，取令牌必然失败。
- `hotspot_manual_required`（平台不让 App 连热点，如 iOS 未配 entitlement）照原流程处理：
  不算失败、什么都不放。

### `lib/src/features/devices/presentation/pairing_page.dart`

撤掉上一版的引导态：删 `_awaitingHotspot` / `_hotspotPoll` / `_pendingRequest` /
`_needsHotspotHandoff` / `_openWifiPanel` / `_HotspotHandoffBar`，以及那条 `resumed`
守卫（没有引导态就不需要）和已无用的 `foundation.dart` import。`_pair()` 回到「校验 →
`_startPairing`」，底部按钮恢复成单独一颗「开始配网」。

### 测试

`test/features/devices/pairing_page_test.dart` 与 `test/widget_test.dart` 直接
`git checkout ad7c6c1 --` 取回"含连热点"那一版——`_connectDeviceHotspot()` 与改写过的
「没连上就停在引导态」都随引导态一起下线，而 `_RefusedHotspotRepository`（覆写
`joinDeviceHotspot` 抛 `hotspot_join_cancelled`）**重新变得有意义**，因为这条路又在流程里了。
`mock_tuya_repository.dart` 保留 `currentSsid` / `wifiPanelOpens` / `pairingSteps`
（前两个无害且以后可能用到，第三个是 `onStep` 那条改动需要的）。

### 文档

- `docs/PRODUCT_RULES.md` 1.2 整节重写成「自动选中，用户最多点一次确认」，并把
  "搜到 ≠ 能连上" 这条事实和上一版的来回都记在里面，避免再推翻。
- `AI_CONTEXT.md` 的动线第 3 步改准为三步，并写明三步各自是哪次实测证明不能少的。

`openWifiPanel`（原生 + repository + state）**保留但不在主流程上**：它是一条随时可用的
退路（比如将来想在失败页给一个「去系统 Wi-Fi 手动连」的入口），留着比以后重写便宜。

## 验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链。静态自检：`state.dart` 与
`pairing_page.dart` 括号配平、与 HEAD 同基线；已确认页面里 `_awaitingHotspot` /
`_hotspotPoll` / `_HotspotHandoffBar` / `_pendingRequest` / `_needsHotspotHandoff` /
`defaultTargetPlatform` 的引用数都归零（不会留下编译不过的残骸）。

## 遗留

- 真机复测三步序列（这是①②③第一次同时到位）。请带回**失败消息整行**（含各步耗时与
  「涂鸦进度」）和 logcat 里的 `pairing step: …`。
- 系统确认框在正常路径上会出现一次；手机记住该热点后可能自动重连 ⇒ 之后零点击。
