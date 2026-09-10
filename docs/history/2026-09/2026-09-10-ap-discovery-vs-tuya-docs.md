# 2026-09-10 搜索设备：扫描排班改均匀、补回取令牌预取，并核对涂鸦文档

## 背景

测试反馈搜索设备的延迟不对称：

1. **先给设备上电、再进 App 点搜索** —— 速度正常。
2. **先进 App 点搜索、再给设备上电** —— 很慢很慢才搜到。

用户追问「是不是频率问题，拉高一点」「涂鸦自家 App 两种场景都是打开就搜到，难道它也是
接了自己 SDK 里的优化方案」，并要求先通读官网文档，按「涂鸦支持的用涂鸦 SDK、不支持
的再自己实现」定方案。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `c7f765d`。

## 诊断

### 不是配额被打满，是排班把预算花错了地方

旧排班是 `0 / 6 / 46 / 86s`（`_earlyForceScans = 2`、`_earlyForceScanGap = 6s`、
`_forceScanGap = 40s`），一轮窗口只发 4 次 `startScan`，**从未超额**。问题在分布：
4 次里有 2 次押在头 6 秒，赌「用户进页面时设备早就开着」。

- 场景 1 这个赌赢了：第一次就扫到 ⇒ 正常。
- 场景 2 这个赌全输：头两次都扫在设备还没广播热点的时刻，白扔；真正有用的第一次
  要等到 46s，错过就是 86s。中间那 40 秒里读缓存只能看到**系统自己**发起的扫描
  结果，系统不扫就什么都没有。

所以症状与排班完全吻合，和限流无关。（2026-09-08 那版 2 秒一扫才是真的把配额烧光。）

### 涂鸦的 AP 配网没有「发现设备」这一步

通读官网相关文档后确认：

- [Wi-Fi 热点模式（Android）](https://developer.tuya.com/cn/docs/app-development/hotspot-mode?id=Kaixk6wxla1oy)、
  扩展 SDK 的热点模式、[iOS 热点模式](https://developer.tuya.com/cn/docs/app-development/hotspot-mode)
  三份文档的步骤次序一致：**取 Token → 用户输入路由器 SSID/密码 → SDK 自己连设备热点
  → 回调 found/registered/initialized**。iOS 那份的时序图最直白：
  `note over app: 用户输入路由器密码` 出现在 `app ->> app: 引导用户连接到设备热点`
  **之前**。
- 新流程原文：「在配网过程中，**SDK 会在指定时间内自动去连接 AP 热点**，如果连上后，
  SDK 内部会去获取设备状态，上报给业务方。」找热点、连热点都在 SDK 内部。
- [设备配网业务实现](https://developer.tuya.com/cn/docs/app-development/extension-sdk-tutorial-deviceconfig?id=Kd8k3w5na6q73)
  里 `ThingActivatorCoreKit.getScanDeviceManager()` 的扫描能力只覆盖
  **蓝牙（MESH / SIG_MESH / SINGLE / BEACON）、有线网关、Zigbee 子设备、Matter**，
  **没有 Wi-Fi 热点（AP）设备的扫描方法**，也完全没有提到 App 需要自己枚举附近 Wi-Fi。
- [设备配网 UI 业务包](https://developer.tuya.com/cn/docs/app-development/deviceconfiguration?id=Ka8qhzk488zyd)
  列出的配网方式里有「自动发现配网」，但官网文档中的自动发现分别落在
  **蓝牙广播**（设备主动发 BLE 广播包）、**有线设备局域网广播**（需手机与设备同网段）、
  **Matter 自发现**（仅 Tuya Matter 设备）和 **Pegasus（天马座）**（需家里已有可中继
  的涂鸦设备）上。

结论：**智能生活 App「打开就发现」用的是蓝牙/局域网/Pegasus 那几条路，不适用于纯
Wi-Fi AP-cfg 设备。** 对 AP 设备它根本不给雷达页，是「选品类 → 输 Wi-Fi 密码」。
因此「搜索设备」这一页是本项目自加的，涂鸦不提供对应能力 —— 按用户定的口径，这一档
只能自己扫，Android 的 4 次 / 2 分钟配额绕不过去。

### 顺带查出的真 bug：新流程把取令牌排到了断网之后

涂鸦文档原文：「开始配网之前，SDK 需要在**联网状态下**从云端获取配网 Token」。

- 原流程 `pairViaHotspot` 内部是「先取令牌、再连热点」，顺序天然正确。
- 改成新流程后，连热点被提前到**搜索页**（`connectDeviceForPairing` →
  `apQueryDeviceWifi`），而取令牌仍留在下一页的 `apStartPairing` 里
  （`MainActivity.kt` 的 `freshActivatorToken()` / `fetchActivatorToken`）。
- 于是实际顺序变成「先连上没有外网的设备热点、再去云端取令牌」。`prepareForPairing()`
  这个本来就是为此准备的方法（它的注释明确写了必须在还连着路由器时跑）在新流程里
  **没有任何调用方**。

## 改动

`lib/src/features/devices/presentation/device_search_page.dart`

1. **主动扫描改均匀铺满**：删掉 `_earlyForceScanGap` / `_earlyForceScans` /
   `_forceScanCount`，`_forceScanGap` 40s → **32s**，排下来 `0 / 32 / 64 / 96 / 128s`。
   第 5 次落在 128s，此时滚动窗口 `[8s, 128s]` 内只有 32/64/96 三次，留 8 秒余量
   （定时器只会偏慢不会偏快，余量只增不减）。
   效果：设备无论何时上电，最多 32 秒被扫到 —— 场景 2 的最坏情况 **86s → 32s**；
   场景 2 的典型情况（设备 20~40s 起热点）也从 46s 降到 32s 以内；场景 1 仍然是
   第一次就扫到，没有损失。
2. **读缓存 2s → 1s**：这是本页唯一能无代价拉高的频率（受配额约束的只有
   `startScan`，读 `scanResults` 不受限）。它决定「某次扫描看到热点」到「列表上出现」
   的延迟。
3. **补回云端预取**：新增 `_prepared`，进页面就 `prepareForPairing()`（取令牌 +
   确认家庭），`_connectAndOpen` 在调 `connectDeviceForPairing` 前 `await` 它。
   两者共用 `_guard` 的单操作锁，不等会被挡成 `busy`；失败不拦路，`apStartPairing`
   仍会自己再取一次，行为不比改之前差。

`lib/src/state.dart`：`probeWifi` 的注释同步到新节奏（1 秒读缓存 / 32 秒真扫）。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链（`which flutter dart` 均为空），
`flutter analyze`、`flutter test`、Kotlin 编译和真机都没跑。改动是常量与排班调整
加一处 `await`，但仍需真机确认，特别是第 3 条（预取与单操作锁的时序）。

## 遗留

- **待定的结构性改动（未做）**：按涂鸦的次序，搜索这一页不该是配网的门槛 ——
  可以进页面就并行发起 SDK 的 `connectDeviceForPairing()`（SDK 自己找热点，不经过
  我们的 `startScan` 配额），扫描只负责「展示扫到了哪台」。这会把配额从关键路径上
  彻底摘掉。没有立刻做的原因：设备未上电时 SDK 会耗掉整个超时，需要配套的重试与
  `boundNetwork` 清理逻辑（`MainActivity.kt` 里已有「上一次失败留下的网络绑定」这类
  注释），本机无法编译验证，盲改风险过高。
- **还需注意**：我们自己的扫描和 SDK 内部可能的扫描**共用同一份 per-app 配额**。
  雷达页把 4 次烧光，理论上会饿死 SDK 的连热点动作。这也是上一条该做的理由之一。
- 待按用户要求：把项目功能点逐条核对涂鸦文档，涂鸦支持的改用涂鸦实现，不支持的
  才自己实现。
- 设备固件 TuyaOS ≥ 3.6.1 仍未与设备团队书面确认（按用户指示假定成立）。

## 回滚

`git revert` 本次提交即可，只动了两份 Dart 文件，无数据与原生改动。
