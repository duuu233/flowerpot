# 2026-09-11 配网回到最稳定那一版：只剩一条路，删掉 1388 行

## 要求

产品：「经过很多次的迭代，确定了安卓绕不开起码弹一次系统框，那就还原回去到最初的配网 1 2 3
三个步骤，但是还是先连设备再 wifi 密码，然后去掉多余的代码……找到最稳定的那一版，允许一次弹
系统框，要最稳定、最简洁的代码，多余的都删除。」

## 删掉了什么

| 删掉的配网路径 | 为什么 |
| --- | --- |
| `pairViaEz`（EZ / SmartConfig） | 真机实测设备不支持 |
| `pairViaDeviceHotspot`（涂鸦「热点配网新流程」：`queryDeviceConfigState` + `startActivator`） | 整条路的前提是"SDK 自己连热点"。涂鸦 2026-09-11 书面确认那句话**说的是设备端**，手机侧不会连 |
| `pairViaActivatorKit`（扩展 SDK `ThingActivatorCoreKit`） | 同上，也要手机先连热点，没有任何额外好处 |
| `WifiManager#connect()` 静默连接探针 | 真机判定：`ActionListener` 无回调、`addNetwork()` 返回 -1 |
| `WifiNetworkSuggestion` | 平台只在它判定"当前最优"时才连，没有 API 能要求立刻连 |

**留下的唯一一条**：`FlowerpotState.pairViaHotspot` —— git 里最后一版配网成功的路径
（`223bdae^`）：取令牌 → 连热点 → `pairWifiDevice`（涂鸦标准 AP）。

连带删掉的：

- Dart：`connectDeviceForPairing` / `deviceWifiNetworks` / `DeviceWifiNetwork` /
  `openWifiPanel` / `onDeviceHotspot` / `refreshOnDeviceHotspot` /
  `_releaseDeviceHotspotPairing` / `_refreshOnDeviceHotspot` / `pairingSteps` 流
- 仓库层：`apQueryDeviceWifi` / `apStartPairing` / `apStopPairing` / `activeStart` /
  `activeStop` / `openWifiPanel` / `pairingSteps`（抽象 + 实现 + mock 三处）
- 原生：上面这些的 handler、`optimizedActivator` / `activeManager` 两个实例字段、
  `releaseOptimizedActivator`、`prefetchDeviceSecurityConfig` + `deviceSecurityConfig`
  （读它的两处都删了，成了死代码）、`EZ_MODE_NAMES` / `DUAL_MODE_NAMES`、
  扩展 SDK 专用的回调分支（`onFind` / `onBind` / `onActiveError` / `onActiveLimited` /
  `onActivatorStatePauseCallback`）与 `beanError` / `textOf`、`Settings` import

净删 **1388 行**，加 160 行。

## 进度回到三步

`PairingStage`：`connectingDevice`（连接设备）/ `sendingWifi`（发送Wi-Fi信息）/
`connectingCloud`（连接云端）。

五步那一版是照智能生活截图做的，后两步依赖新流程的 `onStep` 回调——那条路删了，步数也跟着
回来。第一步的说明文案正好就是原来写的那句：**「系统若弹出连接热点的确认框，请点「连接」」**
——和今天"允许弹一次"的结论天然一致。

## 顺序保留「先连设备，后输密码」

这一点**不跟着回退**（产品明确要求）。好处有两个，所以留着：

1. 把那次系统框挪到用户刚点完设备、注意力还在这件事上的时候；
2. 解掉「手机挂在热点上就带不出当前 Wi-Fi 名」的矛盾——路由器名在**连热点之前**就抓好了
   （`PairingArguments.routerSsid`），用户到下一页只需输密码。

「切换」弹层里的网络列表回到**手机扫到的那份**（`wifiScan.routerNetworks`）；刷新按钮改成
`probeWifi(refresh: true)`。进页面自动弹列表那一套（`_maybeOpenPicker`）删了——SSID 已经填好，
没必要再弹。

## 没删的东西，以及为什么

- **页面内的原生日志框**（`pairingLog` / `_PairingLogBox`）：产品不看 logcat，出错要能截图。
  §4.1 是产品口径，留着。
- **失败诊断串**（`_connectDiagnostic`：原文 + 用时 + 手机当时连在哪）：它原来挂在已删的
  `connectDeviceForPairing` 上，现在改挂到 `connectDeviceHotspot` 的失败分支，继续满足 §4.1。
- **`startActivator` 里的模式查找**（`activatorMode` / `activatorFactory`）：只留 AP 一支，
  但反射那套"候选名逐个试"的写法没动——它是**正在工作的那条路**，为了好看去改它不值得。
- **OTA / 设备详情 / 纪念日**等与配网无关的改动一概没碰。

## 验证

**未验证**（本机没有 Flutter / Dart / Kotlin 工具链）。静态自检（`PRODUCT_RULES` §6 清单）：

1. 九个改动文件的 `{}` `()` `[]` 全部配平；
2. 全仓 grep 确认被删符号**零残留**（含文档注释里的指路），也没有悬空调用
   （`releaseOptimizedActivator` / `newOptimizedActivator` / `beanError` …）；
3. `PairingStage` 三个成员在 `lib/` 里都有人用，没有引用已删的 `deviceScanning` /
   `connectingRouter` / `activating` / `goingOnline`；
4. Kotlin 的 `Settings` import 随 `openWifiPanel` 一起删；`Handler` / `Looper` /
   `SystemClock` / `Intent` 逐个确认仍有使用者；
5. 测试同步改了两处：`state_pairing_test` 的新流程用例换成「连热点 → 配网 → 退出还原网络」；
   `pairing_page_test` 里 `tokenCalls` 从 0 改成 1（`pairViaHotspot` 自己取令牌）。

⚠️ 早就存在的破测试仍未修：`test/widget_test.dart` 还断言已删除的「选择设备」页。
