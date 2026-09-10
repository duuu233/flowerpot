# 2026-09-10（晚，定稿）改回「用户手动点设备行的连接」

## 产品要求

> 原来搜索出的设备有个设备列表，然后旁边有个连接按钮，手动点击，这种方式是对的，改成
> 这种，不要自动连接设备了 …… 后面的流程不变，手动选择设备，然后输入 wifi 密码，然后配网。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `02a38f0`。

## 先把一件事说清楚

产品同时提到「这种也不会出现系统的授权弹出框」——**这一点不成立**。那个框由
`WifiNetworkSpecifier` 触发，与"自动发起还是用户点的"无关，OS 只认"有应用要加入这个
网络"。手动点**不会**让它消失。

但产品的直觉有一半是对的，而且这一半很重要：**自己冒出来的系统框，用户完全不知道发生了
什么**；由用户点按钮触发时，框出现在他刚表达意图的那一刻，体验完全不同。所以这个改动
本身是对的，只是收益在"时机"而不是"有没有"。

唯一真能没有框的情形仍然是"该热点已在手机的已保存网络里"（见 `PRODUCT_RULES.md` 1.2）。

## 改动（把当天那次「自动连热点」整个回退）

### `lib/src/features/devices/presentation/device_search_page.dart`

- `_FoundDeviceTile` 每行右侧加一颗 **`device-search-connect-$index`「连接」**按钮（整行
  仍可点，同一个动作）；原来那个 `chevron_right` 箭头换掉——这一步是用户做决定，按钮比
  箭头更说明"点了会发生什么"。
- `_maybeAutoOpen()` 只负责**停掉扫描**（目标已在眼前，再扫白烧配额），**不再做任何自动
  连接**。删掉 `_connectHotspotThenOffer`、`_hotspotReady`、`_hotspotError`、`_hotspotState`、
  `_autoOpenDelay`、`_autoOpenTimer`、`_connecting`。
- 去掉 `WidgetsBindingObserver` 与 `dispose` 里的网络还原：**本页不再持有任何热点连接**，
  没有网络要还原（那件事回到「连接 Wi-Fi」页负责）。
- 去掉随之无用的 `state.dart` import（`FlowerpotState` 不再被按类型持有）。
- `_SearchActions` 回到「重新扫描 / 下一步」两形态，去掉上一版加的 `onConnect`。
- 副标题改成「点设备右侧的「连接」，然后选择要让它加入的 Wi-Fi 并输入密码。」

### `lib/src/features/devices/presentation/pairing_page.dart`

去掉 `PairingArguments.hotspotConnected` 与 `_maybeOpenPicker()`——热点现在在「开始配网」
那一刻才连，所以进这一页时手机**还在路由器上**，SSID 照常自动带出来，不需要自动弹列表。

### 不动的部分

`pairViaDeviceHotspot` 的三步（① 连热点 ② 建通道查状态 ③ 下发凭据）一行没改——热点本来
就在①连，只是现在它是整条流程里**唯一**一次连接，系统框也只在那一刻出现一次。
「连接 Wi-Fi」页的网络还原（`dispose` / `paused`）也保留，那里才是持有连接的地方。

### 测试

- `device_search_page_test.dart`：用例名与断言改为「列出来、由用户点该行的『连接』」——
  等 1 秒确认**不会自己跳走**，再点 `device-search-connect-0` 才跳，并带上热点名。
- `pairing_page_test.dart`：把上一版那条「没传 hotspotConnected ⇒ 不自动弹列表」的注释改成
  「进页面不会自己弹列表」（断言本身不变，仍然有效）。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。静态自检（按 `PRODUCT_RULES` §6 的清单走）：

1. 四个改动文件括号配平。
2. 删掉的符号逐个搜过，引用全部归零：`_maybeOpenPicker` / `_pickerOffered` /
   `hotspotConnected` / `_hotspotReady` / `_hotspotError` / `_hotspotState` /
   `_connectHotspotThenOffer` / `_autoOpenDelay` / `_autoOpenTimer` / `onConnect` /
   `connectLabel`。
3. 删 import 前确认 `FlowerpotState` 在本页已无按类型使用（只剩注释，已一并删）。
4. 没有引入新语法糖。

## 遗留

- 真机确认：系统框**只在点「开始配网」之后出现一次**；搜索页不再弹任何东西。
- `test/widget_test.dart` 的端到端用例仍是**先前就损坏**的状态（断言已删的「选择设备」页
  与 `pairing-hotspot-step`），未盲改。
