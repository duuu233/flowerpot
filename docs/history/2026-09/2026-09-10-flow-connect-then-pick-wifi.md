# 2026-09-10（晚，定稿）动线改为「先连热点、再选 Wi-Fi」

## 产品给的参照与要求

智能生活的顺序（产品实测）：搜到设备 → 提示「无 4G 信号或信号不佳，建议配置 wi-fi
网络」+ 重试按钮 → 点了弹出 Wi-Fi 列表 → 选自己手机连的那个 Wi-Fi → 输密码 → 配网。

产品按它调整我们的动线：

> 先搜索出设备，然后**自动热点连接这个设备**，然后点击按钮（我这边命名为**连接**），
> 也可以给类似的提示，然后点击弹出 **WIFI 列表**，**这时候就不需要显示设备了**，
> 然后让用户选择 WIFI，然后输入密码，也进行配网流程。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `39d29d6`。

## 可行性核对（产品问「我的理解对不对」）

**理解正确，可以实现，而且这个顺序比原来更稳。** 三点说明：

1. **先连热点解掉一个现有矛盾。** 原顺序是「输密码 → 连热点 → 配网」，而手机一旦挂在
   设备热点上，「带出当前 Wi-Fi 名」只能留空（填热点名等于让设备去连它自己）。新顺序里
   用户本来就要自己选 Wi-Fi，矛盾消失。
2. **有一个硬性前置，顺序上已满足。** 取令牌 / 取安全配置 / 确认家庭都要走云端，必须在
   连热点**之前**完成——一连上热点手机就没外网。这三件事由搜索页进页面时
   `prepareForPairing` 预取，所以只要保证"自动连热点"发生在预取之后即可。
3. **一个风险要兜底。** `WifiNetworkSpecifier` 建的是进程专属的一次性连接，用户在选
   Wi-Fi / 输密码那段时间里可能被系统掉掉。所以 `pairViaDeviceHotspot` 的第①步照常保留
   ——已连就跳过、掉了就重连。
4. **Wi-Fi 列表拿得到**：手机连在设备热点上时扫描照样能用（扫描和关联是两回事），
   `getScanResults` 仍能列出附近路由器。

**一处没照抄**：「无 4G 信号或信号不佳」说的是设备没有蜂窝信号，而**我们的花盆完全没有
蜂窝模块**，照搬会让用户以为它有 4G。换成准确的说法：
「设备本身不联网，需要给它配置一个 Wi-Fi 网络——点「连接」选择网络并输入密码。」

## 改动

### `lib/src/state.dart`

新增 `connectDeviceHotspot({String? hotspotSsid})`——单独连热点、不配网，给搜索页用。
文档注释写明：调用方必须先等 `prepareForPairing()`；连上之后不要以为它一定还在。

### `lib/src/features/devices/presentation/device_search_page.dart`

- `_openPairingWhenReady` → `_connectHotspotThenOffer`：等 `_prepared` → `connectDeviceHotspot`
  → 成功置 `_hotspotReady`、**不再自动跳页**；失败记 `_hotspotError` 并放开 `_autoOpened`
  让用户能重试。
- 状态文案按 `_hotspotError` / `_hotspotReady` / `_connecting || _autoOpened` 三态切换。
- `_SearchActions` 从「二选一」扩成「三选一」，新增 `device-search-connect`
  （文案「连接」／失败时「重试连接」）。
- `_scan()` 复位这三个新状态。
- `_openPairing` 多带一个 `hotspotConnected: _hotspotReady`。

### `lib/src/features/devices/presentation/pairing_page.dart`

- `PairingArguments` 新增 `hotspotConnected`。
- **删掉「已选择设备 xxx」那一行**：设备是在搜索页确认的，这一页只管选网络 + 输密码。
- 新增 `_maybeOpenPicker()`：`hotspotConnected` 为真且 SSID 为空时，进页面就把 Wi-Fi 列表
  弹出来，只弹一次。**刻意用 `hotspotConnected` 而不是"SSID 为空"做闸门**——后者会让
  「手机没连 Wi-Fi」「手机挂在设备热点上」那两条既有用例凭空多出一个弹层。
- `_WifiSelectionSheet` 的根节点加 `pairing-wifi-sheet` key，让"有没有自动弹出"这件事
  可被断言（不加的话那条断言是空的）。

### 测试

- `device_search_page_test.dart` 的「自动带着它进下一步」改写为「自动连上它的热点，再由
  用户点『连接』进下一步」：断言连上后出现 `device-search-connect` 与「已连接『…』」、
  `pairingArguments` 仍是 `'unset'`，点了才跳并带上热点名。
- `pairing_page_test.dart` 的「the connected device … is shown」作废改写为「这一页不再
  重复显示设备」，并顺带断言没传 `hotspotConnected` 时不会自动弹列表。

## 验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链。静态自检：改动的 4 个产品文件 + 2 个
测试文件括号配平；确认 `_openPairingWhenReady` / `pairing-connected-device` 引用已归零。

⚠️ **一个先前就存在的失败**（不是本次造成）：`test/widget_test.dart` 的端到端用例仍在断言
`'请选择需要连接的设备'` 与 `connect-device-0`，而「选择设备」页
（`device_selection_page.dart`）2026-09-10 早些时候已按产品要求删除；同文件还断言
`pairing-hotspot-step`，那个步骤也已删。这条用例从那时起就坏了。没有盲改它——盲写端到端
用例很可能再写坏一个；建议等能跑测试的环境再一并修。

## 遗留

- 真机复测整条新动线，尤其：系统确认框出现的时机（应在搜索页点完设备后）、连上热点后
  Wi-Fi 列表里能不能看到用户的路由器、以及热点连接是否在选网络那段时间里被系统掉掉。
