# 涂鸦能力核对（2026-09-10）

口径：**涂鸦支持的就用涂鸦的 SDK，不支持的再自己实现。**

核对方式是把 `MainActivity.kt` 桥接层真正向涂鸦要的每一项能力，逐条对照
developer.tuya.com 上的官方文档。下面每条都注明依据；**没有依据的写「未核实」，
不猜。** 本机没有 Flutter/Dart/Kotlin 工具链，本文只做静态核对，不含运行验证。

## 一、已经在用涂鸦官方 API（保持现状）

| 功能点 | 桥接方法 | 涂鸦入口 |
| --- | --- | --- |
| 登录 / 注册 / 验证码 / 改密 / 登出 / 注销 / 改昵称 / 当前用户 | `login` `loginWithUid` `register` `sendVerificationCode` `resetPassword` `logout` `cancelAccount` `updateNickname` `currentUser` | `ThingHomeSdk.getUserInstance()` |
| 家庭查询与切换 | `currentHomeId` `setHomeId` `setHomeTag` | `getHomeManagerInstance()` / `newHomeInstance(id)` |
| 设备列表 | `getDevices` | `newHomeInstance(id)` 家庭详情 |
| 重命名 / 移除 / 恢复出厂 | `renameDevice` `removeDevice` `resetFactory` | `newDeviceInstance(devId)` 同名方法 |
| DP 下发与监听 | `publishDps` / `onDpUpdate` `onDevInfoUpdate` `onRemoved` | `newDeviceInstance` + `registerDevListener` |
| 固件检查与升级 | `checkFirmware` `startFirmwareUpgrade` | `newOTAInstance(devId)` |
| 配网取令牌 | `prepareActivatorToken` | `getActivatorInstance().getActivatorToken(homeId, …)` |
| AP 热点配网（新流程） | `apQueryDeviceWifi` `apStartPairing` `apStopPairing` | `ThingApActivatorBuilder` → `newOptimizedActivator` → `queryDeviceConfigState` / `startActivator` |

这一档不需要改动。

## 二、涂鸦不支持，只能自己实现（保留自研）

### 1. AP 待配网设备的「发现」

**已核实涂鸦没有这个能力。**

- [设备配网业务实现](https://developer.tuya.com/cn/docs/app-development/extension-sdk-tutorial-deviceconfig?id=Kd8k3w5na6q73)：
  `ThingActivatorCoreKit.getScanDeviceManager()` 的扫描只覆盖**蓝牙**
  （MESH / SIG_MESH / SINGLE / BEACON）、**有线网关**、**Zigbee 子设备**、**Matter**。
  没有 Wi-Fi 热点（AP）设备的扫描方法，文中也完全没有「App 自行枚举附近 Wi-Fi」这回事。
- 三份热点文档（[Android 热点模式](https://developer.tuya.com/cn/docs/app-development/hotspot-mode?id=Kaixk6wxla1oy)、
  扩展 SDK 热点模式、iOS 热点模式）的步骤次序一致：
  **取 Token → 用户输入路由器 SSID/密码 → SDK 自己连设备热点 → 回调**。
  iOS 那份的时序图最直白：`用户输入路由器密码` 排在 `引导用户连接到设备热点` 之前。
- 涂鸦 UI 业务包列出的「自动发现配网」分别落在**蓝牙广播**、**有线设备局域网广播**、
  **Matter 自发现**、**Pegasus** 上，都不适用于纯 Wi-Fi AP-cfg 设备。

**结论**：`scanWifi`（`WifiManager.startScan` + `scanResults`）属于自研，无可替代。
代价是 **Android 9 起前台应用每 2 分钟只有 4 次 `startScan`** 的配额，绕不过去
（详见 `device_search_page.dart` 的排班注释）。

**推论**：智能生活 App 对 AP 设备根本不给雷达页，「打开就发现」说的是它的蓝牙/局域网
设备，与本产品无关。

### 2. Pegasus（天马座）不适用

Pegasus 是**设备端 / 路由端固件**的能力（TuyaOS 网关 SDK，用 802.11 Beacon /
Probe 帧下发凭据），需要路由器或家里已有的涂鸦设备支持。**App SDK 侧没有对应接口**，
本项目用不上。

### 3. 定制动画的图片同步（`uploadAnimation`）

[设备管理](https://developer.tuya.com/cn/docs/app-development/devicemanage?id=Kceugzegfxjk7)
里没有文件 / 图片 / 大数据传输接口。当前桩位报的
`product_protocol_required`（「图片同步需要设备 PID 对应的文件传输协议」）方向正确
——这属于**设备端 / TuyaOS 侧**要先定义的协议，不是 App SDK 能单方面接的。
**保持现状，等设备端给协议。**

## 三、涂鸦支持但我们没接对（建议改）

### 1. 设备分享挂错了 SDK ⭐

- 现状：`createShareLink` 反射 `ThingDeviceShareManager`（`extension.device.share` /
  `bizbundle.device.share`），两个包都没集成，于是永远返回
  `share_service_unavailable`。
- 官方：**核心 SDK 就有设备分享**，入口 `ThingHomeSdk.getDeviceShareInstance()`，
  方法包括 `addShareWithMemberId()` / `addShareWithHomeId()` /
  `queryUserShareList()` / `removeUserShare()` / `disableDevShare()`
  （见[共享设备](https://developer.tuya.com/cn/docs/app-development/android-saas-smart-protect-device-share?id=Kb5g8yvnikgt9)）。
- **区别在于形态**：核心 SDK 做的是「**按账号 / 家庭分享给某个人**」；
  「**生成一条分享链接**」是业务拓展 SDK 的设备分享组件才有的。
- **待产品确认**：如果需求是「把设备分享给另一个账号」，改用核心 SDK 立刻可用，
  不必集成业务拓展包；如果一定要**链接**，那才需要在涂鸦平台开通并集成业务拓展 SDK。
  在确认之前不动代码。

### 2. `joinDeviceHotspot` 已成回退路径 ⭐

`WifiNetworkSpecifier` + `requestNetwork` 这套自研连热点逻辑，是**系统入网授权框的
唯一来源**。切到热点配网新流程后由 SDK 自己连热点，这条路径只剩 legacy
`pairViaHotspot` 在用，而 UI 已不再调用它。
**建议**：明确标注为「老固件回退路径」或直接删除（连同 `EZ_MODE_NAMES` /
`DUAL_MODE_NAMES` / `"ez" ->` 那批死代码）。删除前需先确认固件 TuyaOS ≥ 3.6.1。

### 3. 设备统计（`getStatistics`）归属应在后端

App SDK 的设备管理文档里**没有**历史数据 / 趋势 / 统计接口；涂鸦的设备统计在
**云服务 API（服务端）**那一侧
（[设备管理云 API](https://developer.tuya.com/cn/docs/iot/open-api/api-list/api/device-management?id=K9g6rfntdz78a)）。
当前桩位的报错文案方向对，但实现路径应该是**后端调涂鸦云 API 再给 App**，
不是在 App 桥接层里补。**需与后端确认归属后再排期。**

### 4. 两个官方接口我们没用（可选增强）

设备管理文档里现成的：

- `requestWifiSignal()` —— 设备侧真实 Wi-Fi 信号强度。设备信息页现在没有这个数据。
- `getOfflineReminderSupportStatus()` —— 离线提醒是否可用。
- `getDp()` —— 单个 DP 主动查询，「针对不主动发送数据的设备」。

都属于「涂鸦有、我们没用」，不是 bug，按产品需要再取。

## 四、结构性待办

**搜索页不该是配网的门槛。** 按涂鸦的次序，AP 配网从来不需要先发现设备。可以改成：
进搜索页就并行发起 SDK 的 `connectDeviceForPairing()`（SDK 自己找热点，不经过我们的
`startScan` 配额），本地扫描只负责「展示扫到了哪台」。这样配额彻底离开关键路径。

未立刻实施的原因：设备未上电时 SDK 会耗掉整个超时，需要配套的重试与 `boundNetwork`
清理逻辑；本机无法编译验证，盲改风险过高。

⚠️ 另一个尚未量化的风险：**我们自己的扫描与 SDK 内部可能的扫描共用同一份 per-app
配额**。雷达页把 4 次烧光，理论上会饿死 SDK 的连热点动作。这也是上面这条该做的理由。

## 未核实项

- SDK 内部到底如何定位设备热点（是否也调 `startScan`）—— 文档只说「SDK 会在指定
  时间内自动去连接 AP 热点」，未展开。
- 设备固件 TuyaOS 是否 ≥ 3.6.1（新流程的前提），仍需设备团队书面确认。
- 本文所有接口签名均来自官方文档，**未在本项目内编译或真机验证**。
