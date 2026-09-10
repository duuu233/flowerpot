# 2026-09-11 「连接」按钮改为在那一刻就连热点（框不再出现在密码之后）

## 产品反馈

> 前面的配网流程还是不对，在输入完 wifi 密码后又弹框设备的授权了，很早的版本是不需要的，
> 前面手动选择连接设备是不是就已经做了这个事情，找一下 git 记录。反正不要系统的设备弹框
> 「要与智能花盆搭配使用的设备 / 取消 / 连接」。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `e01bc8d`。

## 查 git 的结果（产品点名要查的那一条）

被删掉的「选择设备」页（`device_selection_page.dart`，删于 `b951d61`）里那颗
`connect-device-$index` 按钮的实现注释写得很清楚：

> Nothing is "connected" here: joining a hotspot is a system-level action …
> carried so the next page can name the hotspot to join in AP mode.

**所以更早那版的「连接」同样不连热点、只是把热点名带到下一页**——那一版的系统框也出现在
输完密码之后。「很早的版本不需要」最可能是当时测试机**已经保存过该热点**（保存过就由系统
自动重连，不经过任何 App API，自然没框）。

这一条记下来，免得以后再去找那个"不存在的旧实现"。

## 但产品的要求本身是对的

按钮叫「连接」，却什么都不连，框跑到密码之后才弹——用户以为早连上了，又被问一次。
2026-09-10 晚那次为了"改回手动选设备"把连接留在了 `开始配网`，正是这个毛病。

**改法：点「连接」就在那一刻连。** 框于是出现在用户刚表达意图的时候；而配网那一步的第①步
会检测到**已持有这条连接**并原地跳过（靠原生 `boundHotspotSsid` 记账，不依赖读 SSID 的
权限），所以**输完密码不会再弹第二次**。

⚠️ 仍要说清：这不是"消掉框"，是"框只出现一次、且出现在对的时机"。唯一真能没有框的情形
仍然只有"该热点已在手机的已保存网络里"（见 1.2）。

## 连带要解决的副作用

一连上设备热点，手机就离开路由器，「连接 Wi-Fi」页那条"带出当前 Wi-Fi 名"的规则只能留空。
办法是**趁还在路由器上先把名字抓下来带过去**：

- `PairingArguments` 新增 `routerSsid`。
- `_connectAndOpen` 在调 `connectDeviceHotspot` **之前**读 `wifiScan.current`
  （当前就挂在设备热点上时按空处理）。
- `_applyCurrentSsid`：手机还在路由器上就用当前网络，已经挂到热点上了就用 `routerSsid`，
  两者都没有才留空。

用户到下一页仍然看到自己的 Wi-Fi 已经填好，只需输密码。

## 改动清单

`device_search_page.dart`
- 新增 `_connectingIndex`（哪一行在转圈、并挡住期间的重复点击）、`_connectError`、
  `_hotspotState`。
- 新增 `_connectAndOpen(index, hotspot)`：抓路由器名 → `await _prepared` → `connectDeviceHotspot`
  → 成功才 `_openPairing(..., routerSsid: ...)`；失败把原因顶到副标题，用户再点一次即可。
- `_FoundDeviceList` 的 `onSelected` 改为回调**下标**，新增 `busyIndex`；
  `_FoundDeviceTile` 新增 `busy`（按钮转圈）、`onTap` 改为可空（别的行在连时整行不可点）。
- 重新混入 `WidgetsBindingObserver`：`dispose` 与 `paused` 都放掉热点连接
  （`_connectingIndex != null` 时跳过——系统框会让本页 paused，那时放等于撤回刚发出的请求）。
- 副标题：空闲时说"点设备右侧的「连接」…系统会弹一次确认框"；连失败时显示失败原因。
- 重新 import `state.dart`（又要按类型持有 `FlowerpotState` 了）。

`pairing_page.dart`：`PairingArguments.routerSsid` + `_applyCurrentSsid` 的回落。

`device_search_page_test.dart`：点 `device-search-connect-0` 那条补上
`expect(arguments.routerSsid, 'TP-LINK_2.4G')`，并把"用户没点过「就连这台」"那句过时注释改掉。

`docs/PRODUCT_RULES.md`：1.4 动线表整节重写（框出现在第 2 步、第 4 步明确「不会再弹框」），
1.4.1 补上「搜索页点过『连接』之后返回」这条退出路径。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。按 §6 清单自检：

1. 三个产品文件 + 一个测试文件括号配平。
2. 新符号逐个搜过来源与引用：`_connectingIndex` / `_connectError` / `_hotspotState` /
   `_connectAndOpen` / `busyIndex` / `routerSsid` 均只出现在应出现的文件里，无悬空引用。
3. 重新加的 `state.dart` import 确有按类型使用（`FlowerpotState? _hotspotState`）。
4. `InkWell.onTap` 本就是可空类型，改成可空不需要额外处理。
5. 没有引入新语法糖。

## 遗留

- 真机确认：点「连接」时弹一次框；**输完密码点「开始配网」不再弹**；下一页 SSID 已填好。
- 若仍在密码后弹第二次，说明 `boundHotspotSsid` 那条"已持有"判断没命中（比如系统把那条
  连接掉了），看 logcat 的 `hotspot ... already held, reusing` 有没有打出来。
