# 2026-09-10（晚）去掉「读设备扫到的 Wi-Fi 列表」这一步，并收紧配网页间距

## 背景（用户报告）

1. 设备配网页面，中间插图上下的间距太大，首屏展示不完整。
2. 配网提示超时：「设备未能成功连接到当前Wi-Fi网络」。
3. 在搜索设备页发现 1 个设备，然后提示「正在连接【SmaXXXX】」**就卡住了，然后提示超时**。
4. 用户定调：「**并读取他能看到的网络，是不是有问题，只要是当前手机连接的网络就行了，
   不要管其他的网络**」「**当前手机连接的网络就是对的**」。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `7cac9e7`。

## 诊断

第 3 条定位了问题：卡住的位置是**新流程的第一步**，不是配网本身。

搜索页扫到设备后会调 `connectDeviceForPairing()` → `apQueryDeviceWifi` →
`queryDeviceConfigState`，由 SDK 连上设备热点并回读**设备自己扫到的** Wi-Fi 列表。
页面停在「正在连接「smartlife_xxx」…」直到 60 秒超时，**整条动线走不到输密码那一页**。

官方文档对这一步写得很清楚：「该流程针对**新设备固件**才有效，只有新设备固件才支持
…… 待配网设备的应用固件使用的 TuyaOS 版本号，不低于 **3.6.1**。」固件版本一直是按用户
指示**假定**成立的，从未与设备团队确认。老固件上这一步的表现正是 `207206`（设备返回
不能识别的状态）或**超时**。

而这一步换来的唯一收益就是那份「设备视角的 Wi-Fi 列表」——产品已经明确不需要。

## 改动

### 1. 动线：删掉预连热点这一步

- `device_search_page.dart`：`_connectAndOpen()` → 改名 `_openPairingWhenReady()`，
  只 `await _prepared`（取令牌 + 确认家庭，必须在还连着路由器时完成）然后直接
  `_openPairing(hotspot)`。**不再调 `connectDeviceForPairing()`。**
  状态文案去掉「并读取它能看到的网络」那一支。
- `pairing_page.dart`：「切换 Wi-Fi」弹层的数据源从 `state.deviceWifiNetworks` 改回
  `state.wifiScan?.networks`（`probeWifi`），`onRefresh` 不再调
  `connectDeviceForPairing()`。它现在只是「手机没连 Wi-Fi 时让用户自己挑一个」的兜底；
  带出 SSID 的规则（连着就填、没连就留空）本来就只看手机，无需改动。
- `MainActivity.kt`：把配网器的创建从 `apQueryDeviceWifi` 里抽成
  `newOptimizedActivator()`；`apStartWithToken` 原先硬性要求
  `optimizedActivator != null`（否则抛「请先调用 apQueryDeviceWifi 连上设备热点」），
  现在按需新建。依据是官方文档那句「**在配网过程中，SDK 会在指定时间内自动去连接
  AP 热点**」——连热点发生在 `startActivator` 内部，不是查询那一步的副作用。

`connectDeviceForPairing` / `apQueryDeviceWifi` / `deviceWifiNetworks` 代码全部保留，
只是已无 UI 调用方；要回退只需换调用点。

### 2. 失败原因：补齐涂鸦 207xxx 失败码

`pairing_failure_page.dart` 的 `hintFor` 之前一个 207xxx 都没映射，所以任何新流程失败
都只剩一句笼统的「设备未能成功连接到当前Wi-Fi网络」，**看不出是密码错、找不到路由器，
还是固件不支持**。按官方错误码表（存档 `docs/reference/tuya-ap-mode-android.md`）补齐
207201 / 207206 / 207207 / 207209 / 207210 / 207211 / 207212 / 207213 / 207214 /
207215 / 207216 / 207218，每条都给一句能照着做的话；207206 直接点出固件版本问题。

### 3. 间距：配网进度页进首屏

`widgets/pairing_progress_view.dart` 的 `build` 改用 `LayoutBuilder`：

| | 改前 | 改后（常规 / 矮屏 `maxHeight < 700`） |
| --- | --- | --- |
| 顶部留白 | 40 | 20 / 12 |
| 插图高度 | 220 | 190 / 150 |
| 插图下方 | 24 | 16 / 12 |
| 标题下方 | 10 | 8 |
| 卡片上方 | 24 | 20 / 16 |
| 卡片内边距 | 20 | 上下 18 |
| 卡片下方 | 28 | 20 / 16 |
| 底部留白 | 32 | 24 / 20 |

纵向合计省下约 90px（矮屏约 130px），375×812 上三步进度与「取消配网」完整进首屏。
理由写进了注释：正在配网时滚走的恰好是用户要盯的那几步。

## 验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链，`flutter analyze`、`flutter test`
与真机都没跑。只做了静态自检：

- 五个改动文件的括号配平检查全部通过。
- 核对了现有测试：`state_pairing_test.dart` 直接测 `connectDeviceForPairing`（方法保留，
  不受影响）；`device_search_page_test.dart:75` 用
  `textContaining('正在连接「SmartLife-A1B2」')`，新文案仍包含该子串；
  `pairing-progress-title` / `pairing-progress-cancel` / `pairing-progress-view`
  三个 key 与「预计需要10-30秒，请勿关闭页面」文案都保留。

## 遗留

- **配网本身能不能成，仍未验证。** 这次只是把卡死的前置步骤去掉；`startActivator`
  是否真的会自己连上 AP 热点，只有真机能回答。若它同样依赖 ≥ 3.6.1 的固件，
  就必须回到原流程（`pairViaHotspot` + `joinDeviceHotspot`，代价是系统入网授权框）
  ——那套代码都还在。
- ~~请设备团队确认固件 TuyaOS 版本。~~ **2026-09-10 已确认 > 3.6.1。** 这推翻了本文
  原先的首要假设：卡住**不是**固件不支持。真正的原因应是 `queryDeviceConfigState`
  要求手机**已经连在设备热点上**才问得到设备——文档里「SDK 会在指定时间内自动去连接
  AP 热点」那句写在*配网过程*（`startActivator`）里，不是查询那一步的保证。当时手机还
  连着路由器，于是这一步没有对象可问，一直等到超时。结论不变：这一步该去掉。
- 固件既然是新的，新流程该带的就带齐了：补上官方流程开头的 `getDeviceSecurityConfigs()`
  预取（见 `2026-09-10-ap-security-config.md`）。
- 下次失败请把失败页括号里的**失败码**带回来，现在它会直接对应到原因。

## 回滚

`git revert` 本次提交。改动涉及 4 个 Dart 文件 + 1 个 Kotlin 文件，无数据迁移。
