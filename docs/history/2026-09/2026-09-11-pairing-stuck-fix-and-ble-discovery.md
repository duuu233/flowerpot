# 配网「输完密码卡住」的修复 + BLE 发现通道

> 文档类型：Historical Change Record
> 日期：2026-09-11
> 环境：SSH
> 分支与起始版本：main / `2b0a4b8`
> 范围：`lib/src/features/devices/presentation`、`lib/src/state.dart`、`lib/src/tuya/*`、Android 桥接、iOS 桥接
> 当前权威文档：`AI_CONTEXT.md`、`docs/PRODUCT_RULES.md`

## 背景与目标

四件事，按测试反馈的顺序：

1. **「填了 Wi-Fi 密码，点下一步就卡住」**——以前是能配网的，属于回归；
2. 按涂鸦官方 4 步重新梳理配网流程，**把多余的代码删掉**；
3. 搜索页试试**用 BLE 扫描**发现设备，测设备到底支不支持；
4. 进一步走**双模优化路径**：BLE 扫到 → 判 `supportWifiList` → `queryWifiListForDeviceScan`
   拿设备自己扫到的 Wi-Fi 列表，绕开系统 Wi-Fi scan 的频次限制。

## 变更内容

### 1. 卡住的根因：`aef6ccd` 把两行删掉了

`_PairingPageState._pair()` 里这两行被 2026-09-11 那次「净删 1388 行」的大重构
（`aef6ccd`）连同上面一整段注释一起删掉了，替换进来的新注释没有把它们带回来：

```dart
_pairingState = state;
setState(() => _pairing = true);
```

`build()` 靠 `_pairing` 决定盖不盖 `PairingProgressView`。它恒为 false，于是：

- **页面不换**。点下「开始配网」之后还停在输密码那一屏，只有按钮里转一个圈，而
  `pairViaHotspot` 最长要跑满 `pairingDeadline`（150 秒）才回来——中间没有任何进度、
  也没有「取消配网」。报上来就是「卡住了」。
- **「取消配网」够不到**。`_pairingState` 为 null，`_cancelPairing()` 直接 return。
- **退出本页走错分支**。`dispose()` 里 `_pairingState == null` 会去
  `releaseDeviceHotspot()` 而不是 `cancelPairing()`——activator 继续跑满两分钟。
- **切后台会把通道掐断**。`didChangeAppLifecycleState` 的 `paused` 分支靠
  `if (_pairing) return` 保护，`_pairing` 是 false ⇒ 正在下发凭据时去放热点。
  **这一条会让配网真的失败，不只是看起来卡住。**

修复即按 `223bdae^`（git 里最后一版配网成功的代码）原样恢复这两行，并在原地写清楚
它们为什么不能省。

**这个回归本来能被现有用例挡住**：`test/features/devices/pairing_page_test.dart` 的
「leaving the page during pairing cancels it」在当前代码上必然失败（`cancelCalls` 会是
0、`state.busy` 停在 true）——只是本机没有 Flutter 工具链，那轮改完没跑过测试。本次
另给该用例补了三条**直指症状**的断言（点下按钮后进度页、标题、「取消配网」都要在）。

### 2. 配网流程对照官方 4 步

| 官方步骤 | 本仓库在哪 | 说明 |
| --- | --- | --- |
| ① 设备置为 AP 模式 | 无需 App 参与 | 产品口径：**设备开机就一定可配网**，不长按、不复位 |
| ② 手机连设备热点 | 搜索页那颗「连接」→ `connectDeviceHotspot` → `_joinHotspotForPairing` | Android 10+ 必弹一次系统入网授权框，产品口径是把它**收在这一颗按钮上** |
| ③ 取 Token + 收集 SSID/密码 | `prepareForPairing()`（搜索页进页面就预取）+ 「连接 Wi-Fi」页输入 | ⚠️ **顺序与官方步骤表相反，而且必须相反**：取令牌要走云端，一连上设备热点手机就没有外网了 |
| ④ `ApActivatorBuilder` 发起配网 | `pairViaHotspot` → `_pairInternal` → 原生 `startActivator` | `setSsid`/`setPassword`/`setToken`/`setTimeOut(120L)`/`setActivatorModel(THING_AP)`/`setListener`，然后 `start()` |

差异只有一处、且是有意的：**③ 排在 ② 之前**。官方步骤表把取 Token 排在连热点之后，
那样走不通——这条已经在 `prepareForPairing` 与搜索页 `_prepared` 的注释里写死了。

超时口径：Android `setTimeOut(120L)`（秒），iOS `timeout: 120`。官方建议 60 秒；
**本轮没有改**，改超时会动到已经验证过能配上的那条路径，留到真机上单独验。

### 3. 删掉的多余代码（配网路径）

| 删掉的 | 为什么是多余的 |
| --- | --- |
| `FlowerpotState.pairDevice(PairingRequest)` | 全仓零调用。`pairViaHotspot` 直接走 `_pairInternal` |
| `PairingRequest.mode` / `isAp` + 通道里的 `'mode'` | 只剩 `'ap'` 一个取值；Android 侧 `2b0a4b8` 已经不读它，iOS 拿它在 EZ/AP 之间挑——而 EZ 整条路早删了 |
| iOS `args["mode"] == "ez" ? EZ : AP` | 同上，改成写死 `ThingActivatorModeAP` |
| `PairingArguments.deviceName` | 搜索页一直在传，可「连接 Wi-Fi」页 2026-09-10 起就不画「已选择设备 xxx」了，没有任何读取点 |
| `_PairingHintCard`（配网页） | 手动热点那张提示卡是它最后一个调用点，随 `aef6ccd` 删掉后成了孤儿类 |
| 三段悬空文档注释 | `aef6ccd` 的删除脚本把函数删了、KDoc/DartDoc 留在原地，分别粘在 `prepareForPairing`、`_connectAndOpen`、`_connectFailureHint` 头上，还留下两行重复标题 |

### 4. BLE 发现通道（新增，**与 Wi-Fi 并行，不替换**）

原生（`MainActivity.kt`，沿用反射风格，**没有新增任何 gradle 依赖**——蓝牙模块本来就在
`thingsmart 7.5.1` 伞包的依赖里）：

- `bleProbe` → `getBleOperator().isBleSupported()/isBluetoothOpened()`，
  **三种不可用分开报**（包里没模块 / 手机没硬件 / 蓝牙没开）；
- `startBleScan` → `LeScanSetting.Builder().setTimeout(ms).setRepeatFilter(false)
  .addScanType(ScanType.SINGLE).build()` + `startLeScan(setting, ThingBleScanResponse)`，
  扫到的设备**逐台**从事件通道推给 Dart（`type = bleDevice`），不攒到扫完；
- `stopBleScan` → `stopLeScan()`，并接进 `releaseDeviceListeners()`；
- `queryDeviceWifiOverBle` → `getBleManager().queryWifiListForDeviceScan(QueryWifiSetting,
  IThingResultCallback)`，`QueryWifiSetting` 用 BLE 扫到的 `uuid`。

`supportWifiList` 取自 `CombosFlagCapability.isCapabilityEnable(bean.getFlag(),
CombosFlagCapability.SCAN_WIFI)`——就是「固件 ≥ TuyaOS 3.6.1 才有」的那一位。**读不到
常量时按 false 报**：宁可回落到 Wi-Fi 扫描，也不要拿一个猜出来的能力位调下去让用户等
一次超时。

权限：BLE 走的是另一套（Android 12+ `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`，11 及以下
`ACCESS_FINE_LOCATION`），清单里四条早就声明好了、`BLUETOOTH_SCAN` 带 `neverForLocation`
所以 12+ 不再要定位。权限被拒的报错从「配网需要定位或附近 Wi-Fi 设备权限」改成**列出具体
是哪一条**。

Dart：`BleAvailability` / `BleDevice` / `DeviceWifiNetwork` 三个模型，仓库四个方法 +
`bleDevices` 流，状态层 `probeBle` / `startBleDiscovery` / `stopBleDiscovery` /
`loadDeviceWifiList`（**都不占 `_guard` 的 busy 锁**，理由与 `probeWifi` 相同）。
`bleDevices` 按 uuid 去重、信号强的在前、**已绑定的不列**。

UI：搜索页多一张 `_BleFindingsCard`——BLE 可用性一行、扫到的每台一行（信号 /
`supportWifiList` / flag / pid / uuid，等宽字体可截图）、每行一颗「查Wi-Fi」，结果与
失败原文都画在卡里。**配网流程一点没动**，这张卡目前只回答两个问题：设备有没有在广播
BLE、它的固件支不支持回报 Wi-Fi 列表。

## 关键决策

- **BLE 不替换 Wi-Fi 扫描，先并行跑。** 用户口径是「前面的逻辑先放着，假如不支持再切
  回来」。所以这一版 BLE 只做发现与查列表，配网仍是 AP 那条唯一路径。
- **反射目标全部解包核对过，不采信任何口头/AI 说法。** 本项目已经被涂鸦官方 AI 编造的
  API 坑过一次（`ThingSmartHotspotCredentialKit`，Maven 与其自己给的文档里都是 0 次）。
  这次用新写的 `tools/aar_class_dump.py`（纯标准库解析 `.class`，**不依赖 JDK**——本机
  连 JRE 都没有）把 7.5.1 的蓝牙 AAR 逐个拆开确认：
  `ThingHomeSdk.getBleOperator()/getBleManager()`、
  `IThingBleOperator.startLeScan(LeScanSetting, BleScanResponse)` / `stopLeScan()` /
  `isBleSupported()` / `isBluetoothOpened()`、`LeScanSetting$Builder` 的六个 setter、
  `ScanType.SINGLE`、`ScanDeviceBean` 的 getter、`CombosFlagCapability.SCAN_WIFI` 与
  `isCapabilityEnable(int,int)`、`QueryWifiSetting$Builder`、
  `IThingBleManager.queryWifiListForDeviceScan(QueryWifiSetting, IThingResultCallback)`
  ——**全部存在**。
- **`queryWifiListForDeviceScan` 的返回类型没写死**。SDK 没给泛型线索，`bleWifiList` 按
  List/数组/单值都兜一遍，并把每项的 `toString()` 原样带上（`raw` 字段）：真机上一眼就
  能看出这一版给的是什么 bean，比在代码里猜字段名快。
- **和 `aef6ccd` 删掉的那条「新流程」不是一回事。** 那条死在「指望 SDK 自己去连 **Wi-Fi
  热点**」；这条是先建 **BLE** 连接再问它要列表，根本不碰 Wi-Fi 热点。

## 外部操作

- 从涂鸦官方 Maven（`maven-commercial-releases`）下载 7.5.1 的
  `thingsmart` / `thingsmart-bluetooth-api` / `thingsmart-bluetooth-business-api` /
  `thingsmart-homelib(-api)` 解包核对类签名，**核对完已删除，未入库**。

## 验证结果

- **本机没有 Flutter / Dart / Android / Kotlin / JDK 工具链**，`flutter analyze`、
  `flutter test`、Kotlin 编译、真机**全部未执行**。
- 做了的静态自检：
  - 括号配平——按「与改前相比有没有新增不配平」比对，9 个改动文件全部持平；
  - `tools/kt_dangling_refs.py`（块注释配平 + 作用域内悬空引用）在 `MainActivity.kt` 上
    通过；
  - 被删符号全仓零残留：`pairDevice` / `request.mode` / `.isAp` /
    `PairingArguments.deviceName` / `_PairingHintCard` / `pairing-hotspot-manual`；
  - 悬空 / 重复 DartDoc 扫描：`lib/` 零命中。
- 用例已同步：`pairing_page_test.dart` 补三条进度页断言、去掉已删字段；
  `state_pairing_test.dart` 新增两条 BLE 用例（逐台进列表 + 已绑不列 + 退出停扫；
  老固件直接拒、新固件拿回列表）；`MockTuyaRepository` 补四个方法与
  `pushBleDevice` / `bleScanStarts` / `bleScanStops` 等断言钩子。

## 未完成项与风险

1. **配网那两行必须真机回归**——这是本轮唯一确定的线上问题修复。
2. **BLE 全部未真机验证**，两条硬风险：反射签名虽已解包核对，但**参数装箱与运行时行为
   没有编译期保护**；`queryWifiListForDeviceScan` 的回调泛型是推的。
3. `setTimeOut` 仍是 120 秒（官方建议 60），本轮有意没动。
4. 手动热点回落（`hotspot_manual_required`）在状态层还留着（iOS / Android 9 唯一的路），
   但**配网页已经不认它了**，会直接进失败页显示那段引导文案。产品口径是「不再考虑
   Android 9 及以下」，iOS 侧尚未决策。

## 回滚或恢复

- 只回滚 BLE：删掉 `MainActivity.kt` 的「BLE 发现」整节与分发表四行、Dart 三个模型、
  仓库四方法、状态层那一节、搜索页 `_BleFindingsCard` 与两个方法。配网路径不受影响。
- 卡住那条修复**不要回滚**。
