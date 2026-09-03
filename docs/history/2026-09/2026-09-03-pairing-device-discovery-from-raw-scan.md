# 配网搜索页改用原始扫描结果找设备

> 文档类型：Historical Change Record
> 日期：2026-09-03
> 环境：SSH（无 Flutter/Dart 工具链、无 Android SDK）
> 分支与起始版本：main / ab5eb96
> 范围：`lib/src/tuya`、配网三页、Android 桥接 `scanWifi`
> 当前权威文档：`docs/TUYA_SDK_SETUP.md` 5.3 与 6.3

## 背景与目标

真机反馈：涂鸦 SDK 联调页上手机号验证码登录、「扫描附近 Wi-Fi」能看到设备热点（形如 `SmartLift-8987`）、填路由器 Wi-Fi 名称与密码后 `pairViaHotspot` 配网成功；但走产品动线时「搜索设备」和「选择设备」两页一台设备都列不出来。同一台手机、同一个桥接方法，差别只在两页对扫描结果的处理，要求把联调页那套「看到什么就列什么」的逻辑搬到产品页。

比对后确认两页与联调页的差异有三处，都会让设备从产品动线上消失：

1. 联调页列的是 `WifiScan.networks` 原始结果；两个产品页只列 `deviceHotspots`，即命中 SSID 前缀白名单的那些。
2. 白名单要求 `smartlife` 开头，`SmartLift-…` 这种量产件上的写法直接落在名单外。
3. Android 桥接 `scanWifi` 在 `startScan()` 之后立刻读 `scanResults`。`startScan()` 是异步的，读到的是上一轮缓存——设备刚长按进入配网状态时，缓存里还没有它的热点；联调页是用户过一会儿手动点的，缓存已经刷新，所以能看到。

## 变更内容

- `lib/src/tuya/tuya_models.dart`
  - `WifiNetwork.isDeviceHotspotName` 改为忽略大小写与 `-`/`_`/空格后匹配 `smartlif`（同时覆盖 `SmartLife-…` 与 `SmartLift-…`）、`tuya`、`ysplanter`，`ty_`/`ty-` 保留分隔符以免吃掉普通路由器名。
  - 新增 `WifiScan.otherNetworks`：扫描结果里未被识别为热点、且不是 5G（频率 < 2500，未知频段保留）的网络，按信号去重排序，作为手动挑选清单。
  - 新增 `WifiNetwork.hotspotJoinPrefix = 'SmartLi'`，取代散落的 `'SmartLife-'` 字面量。
- `lib/src/features/devices/presentation/device_selection_page.dart`
  - 认出热点时照旧只列热点，底部新增「设备不在上面？显示附近全部网络」展开 `otherNetworks`。
  - 一个都没认出来时直接列原始扫描结果，并加一张说明卡告诉用户设备热点长什么样；未识别行用 Wi-Fi 图标和次级文字与真热点区分。
  - 空态、重新扫描与「设备已在配网状态，继续」保留；「未发现配网中的设备」只在真的一行都列不出来时出现。
- `lib/src/features/devices/presentation/device_search_page.dart`：扫到过 2.4G 网络但没认出热点时，除重新扫描和手动继续外增加「从附近网络中手动选择设备」，进选择页按名字挑；文案同步改成「没有认得出的设备热点」。
- `lib/src/state.dart`、`pairing_page.dart`：前缀兜底改用 `WifiNetwork.hotspotJoinPrefix`；手动连热点提示不再只说 `SmartLife-` 一种写法。
- `android/.../MainActivity.kt`：`scanWifi` 在 `startScan()` 后注册 `SCAN_RESULTS_AVAILABLE_ACTION` 广播，最多等 `SCAN_RESULT_WAIT_MS`（5 秒）拿本轮结果再回；`startScan()` 被限流返回 false 时不等待，直接回缓存。快照读取抽成 `wifiSnapshot`。Android 13+ 用 `RECEIVER_NOT_EXPORTED` 注册，注册失败也不影响回包。
- 测试：`test/tuya/wifi_scan_test.dart` 补热点命名变体与 `otherNetworks`；两个页面测试补「SmartLift 也算热点」「一个都没认出来时回退到原始扫描」「展开全部网络」「搜索页手动选择入口」，并把原「没有热点就是空态」的用例改成只在没有 2.4G 网络时成立。
- 文档：`docs/TUYA_SDK_SETUP.md` 5.3 补 `startScan` 异步与前缀清单的性质，6.3 表格与边界条目按新行为重写；`AI_CONTEXT.md` 第 9 节更新对应风险项。

## 关键决策

- **前缀白名单降级为排序依据，不再是门禁**。固件换个热点名就能让整条动线报「没有设备」，而那台设备明明在扫描结果里。识别命中只决定排在前面和图标，识别不中仍然可以被用户挑出来。
- **手动挑中的名字按精确 SSID 连热点**，不走前缀匹配：`joinDeviceHotspot(ssid:)` 精确匹配，系统找不到才回 `onUnavailable`。只有完全没有名字时才退到 `SmartLi` 前缀，由系统弹框列出匹配项。
- **手动清单滤掉 5G**。设备 AP 只可能是 2.4G，列 5G 只会让用户挑到必然失败的那一项；频段未知（iOS 风格的空频率）保留。
- **等广播而不是轮询**。`SCAN_RESULTS_AVAILABLE` 是系统本来就会发的，等一轮比定时重扫更省电，也不会与 Android 9 起的扫描频率限制打架；限流时立刻回缓存，页面不会白等 5 秒。
- 没有引入定时自动重扫：那会让所有 `pumpAndSettle` 的页面测试挂在待处理定时器上，收益也只是省一次点击。

## 外部操作

无。未连真机、未提交、未推送。

## 验证结果

- 静态复核：改动文件逐处对照调用方（`FlowerpotState.pairViaHotspot`、`PairingArguments.hotspotSsid`、三页导航参数）核对，未发现签名或路由不一致。
- **未执行** `dart format`、`flutter analyze`、`flutter test`、Android 构建：本机 PATH 中没有 Flutter/Dart，也没有 Android SDK。测试文件按新行为改好但一次都没跑过。

## 未完成项与风险

- 全部改动都需要在有工具链的机器上补跑 `dart format lib test`、`flutter analyze lib test`、`flutter test`，Kotlin 侧需要一次 `flutter build apk` 级别的编译验证。
- `SCAN_RESULTS_AVAILABLE` 等待的 5 秒上限是估计值，未在真机测过实际扫描耗时；限流场景下的表现同样未验证。
- Android 13+ 用 `RECEIVER_NOT_EXPORTED` 接收系统广播依赖框架对受保护广播的豁免，未在真机确认能收到。
- 真机上设备热点的真实 SSID 仍未确认（反馈里写的是 `SmartLift-8987`，与联调页截图口径可能有出入）。即使前缀仍不命中，选择页的原始扫描结果也能覆盖，但白名单是否需要再补一条要以真机为准。
- iOS 不返回附近网络列表，本次改动对 iOS 只影响文案，搜索与选择页在 iOS 上仍然只能走手动继续。

## 回滚或恢复

改动集中在上列文件，`git checkout --` 逐个文件即可回到 ab5eb96 的行为。回滚后 `WifiNetwork.hotspotJoinPrefix` 的引用会一起消失，无需额外清理。
