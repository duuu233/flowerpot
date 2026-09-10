# 2026-09-11 配网前先确认手机在设备热点上；失败消息带上当时连的网络

## 现象

去掉 `WifiNetworkSpecifier` 之后复测，仍然是：

```
配网任务整体超时，设备全程没有报过进展…（207220）
失败 45072ms
```

并且产品补了一句关键信息：**「以前都可以直接配网的」**。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `74f826d`。

## 判读

耗时行只有「失败 45072ms」，没有「连设备」——说明 `queryDeviceConfigState` 跑满我们给的
45 秒超时，一直没能和设备说上话；设备侧一个 207xxx 具体码都没回（那些码全是"设备收到
配网信息之后"的），也就是**通道从头到尾没建起来**。

### 一个能解释全部现象的假设

AP 配网的前提是**手机已经连在设备热点上**。现在没有任何东西把它连过去（App 不能调
`WifiNetworkSpecifier`，SDK 实测也没连），所以 45 秒空等是必然的。

而「以前都可以」＋「以前也没有框」同时成立的唯一解释是：**当时那台手机已经"保存"过这个
热点**——设备一开机系统就自动重连上去，旧代码里的 `_joinHotspotForPairing` 检测到
「已经在目标热点上」直接跳过 `requestNetwork`，于是**既没有框、又连着热点、配网成功**。
现在手机没在热点上（保存被清了 / 没自动重连 / SSID 变了），链条就断在第一步。

这个假设可以被验证，所以这一轮先把**证据**做出来，而不是再猜。

## 改动

### `lib/src/state.dart`

1. **失败消息带上「手机当时连在哪个网络」**。`withSteps` 末尾追加
   `手机在「xxx」(设备热点)` / `(不是设备热点)` / `手机网络未知`。
   这一项比失败码更能定位：如果显示的是路由器名，就说明手机从头到尾没连过去，别的都不用看。
2. **开始配网前做前置检查**：`_refreshOnDeviceHotspot()`（只读扫描缓存，不发起扫描、不占
   配额，也不走 `_guard`——那把锁正被配网占着）→ 若 `!onDeviceHotspot` 就**立刻**抛
   `not_on_device_hotspot`，消息里写清当前连的是什么、该去连哪个热点、以及"连过一次系统
   会记住"。**不让用户空等 45 秒再收一句 207220。**
3. 新增公开常量 `FlowerpotState.notOnHotspotCode` 供页面判别。

### `lib/src/features/devices/presentation/pairing_page.dart`

- 拿到 `not_on_device_hotspot` **不跳失败页**——这不是"配网失败"，是"还没开始"，跳过去只会
  让用户以为配不上了。改为就地把原因画在「开始配网」上方，并给一颗
  **「打开系统 Wi-Fi 列表」**（`pairing-open-wifi-panel`）。
- `_openWifiPanel()` 复用早先保留的 `openWifiPanel` 桥接
  （`Settings.Panel.ACTION_INTERNET_CONNECTIVITY`，浮在 App 之上的面板，不是授权框）。
  **这样连上的网络会被系统保存**，于是下一次配网就回到"手机自动连上、全自动无框"那条路。
- 再点「开始配网」时清掉上一次的提示。

### `pairing_failure_page.dart`

给 `not_on_device_hotspot` 补一条兜底映射（正常路径不会跳到那里）。

### `docs/PRODUCT_RULES.md`

1.2 增加「**那么谁把手机连到设备热点上？**」一节，把两条路（已保存网络自动连 / 用户在系统
Wi-Fi 面板连一次）和"连过一次之后就全自动"写清楚，并明确**开始配网前必须先检查、不在就立刻
提示**。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。按 §6 清单自检：

1. 三个改动文件括号配平，`state.dart` 与 HEAD 同基线。
2. 新符号逐个搜过：`notOnHotspotCode`（state + pairing_page）、`_refreshOnDeviceHotspot`、
   `_needHotspotHint`、`_openWifiPanel` 均无悬空引用；顺手删掉了多余的私有别名
   `_notOnHotspotCode`。
3. `openWifiPanel` 在抽象、实现、mock 三处都有。
4. **没有**用 if-case 模式那类新语法（第一版写了 `if (x case final String y)`，已改成
   `!= null` + `!`）。

## 遗留：请带回这两样

1. **失败消息整行**——现在末尾会写「手机在「xxx」(不是设备热点)」。若确实是路由器名，
   假设成立，链条断在"没人把手机连到热点"。
2. **设置 → WLAN → 已保存的网络**里有没有 `smartlife_…`。有 ⇒ 进一步印证"以前能成"的原因。

若假设成立，产品需要在两条里选一条（两条都**没有系统授权框**）：
- **A**：保持现在这样——不在热点上就提示 + 「打开系统 Wi-Fi 列表」，用户连一次，之后系统
  记住、全自动。
- **B**：把引导做进搜索页，点「连接」时就拉面板，用户连完回来直接输密码。

A 已经实现；B 是 A 的位置前移，需要产品决定。
