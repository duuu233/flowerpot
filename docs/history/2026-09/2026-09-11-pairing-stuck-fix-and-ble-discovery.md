# 配网「输完密码卡住」的修复 + 蓝牙（双模）配网改造

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

### 4. 蓝牙（双模）配网 —— **新的主路径**

固件方已确认**支持蓝牙配网**，所以这一版不是「加一条并行的发现通道」，而是把整条动线
换成双模优先、AP 回落。

**完整动线**（对应你给的三步，全部落在真实页面上，没有任何调试面板）：

1. **BLE 扫描发现设备** —— 搜索页进页面就开扫，扫到的设备直接进「已发现设备」列表
   （行上标蓝牙图标 + 信号 + 是否可直接读 Wi-Fi 列表）。**扫到 BLE 就只列 BLE**，
   一台都没有才回落 Wi-Fi 热点那份；
2. **判 `supportWifiList`** —— 取自 `ScanDeviceBean.getFlag()` 的
   `CombosFlagCapability.SCAN_WIFI` 位（固件 TuyaOS ≥ 3.6.1）；
3. **`queryDeviceConfigState()` 拿设备扫到的 Wi-Fi 列表** —— 用户点「连接」时触发，
   `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder, IThingResultCallback)`，
   builder 直接吃 BLE 扫到的那个 `ScanDeviceBean`，**建本地蓝牙连接**问设备要列表，
   完全不走系统 Wi-Fi scan ⇒ 与「2 分钟 4 次 `startScan`」那条配额彻底无关。
   拿到的列表带进下一页，「切换」弹层列的就是它；
4. **配网** —— `IMultiModeActivator.startActivator(MultiModeActivatorBean, …)`：
   ssid / pwd / token / homeId / scanDeviceBean 经蓝牙交给设备。

双模相对 AP 少掉的不只是几步：

| | AP（`pairViaHotspot`） | 双模（`pairViaBle`） |
| --- | --- | --- |
| 系统入网授权框 | **必弹一次** | **没有** |
| 要先知道热点确切 SSID | 要（Android 不接受前缀） | 不要 |
| 手机要不要离开路由器 | 要（那段没有外网） | 不要 |
| 发现速度 | 受 Wi-Fi 扫描配额 | 只受 BLE 广播 |

### 4.1.1 抢答窗口：别让 Wi-Fi 抢在 BLE 前面答

「优先走蓝牙」在代码里有一条不显眼的缝：两条通道并行开，可 **Wi-Fi 那条会先答**——
进页面第一件事就是读系统扫描缓存（不占配额、几乎不耗时），而缓存里往往**已经**有设备
热点了（系统自己、设置页、别的应用一直在扫）。那一瞬间列表先画出 AP 那一行，用户一点，
整条流程就掉进了更差的那条：多一个系统入网授权框、手机还要离开路由器、还得先拿到确切
热点名。

补法是给蓝牙一个 **4 秒抢答窗口**（`_bleGrace`）：BLE 还在扫、且窗口没过时，列表**先不画
Wi-Fi 热点**。BLE 广播是设备主动周期性发的，双模设备通常一两秒就出现；4 秒还没有，多半
就不是双模设备，那时回落到热点列表。**蓝牙用不了时一秒都不压**（`_bleScanStartedAt` 只
在真的扫起来才置位），窗口到点由 `_bleGraceTimer` 主动重画一次——否则窗口期内两条都没
新结果时没人触发重建，热点列表会被一直压着。

**Wi-Fi 扫描的节奏没动**（进页面免费读缓存 → 32 秒一次真扫 + 1 秒一次读缓存）。它现在是
回落路径，但必须保持"随时可用"：蓝牙关着时它就是唯一的路。为省一次配额去推迟首扫，只会
在真正需要它的那次多等几十秒——那正是 09-10 踩过的坑。

### 4.2 「自动优选」要覆盖失败之后，不只是发现阶段

双模的定义是「设备同时支持 Wi-Fi（AP/EZ）+ 蓝牙，**App 自动优选最佳方式，提升配网成功
率**」。第一版的优选只发生在**发现阶段**（扫到 BLE 就走蓝牙，没扫到才走 AP），蓝牙真的
没配成时**一条退路都没有**——那恰恰是「提升成功率」最该覆盖的一段。补了两处：

1. **「重新配网」照原样重来。** 原来失败页只把 `request` 带回去，于是走蓝牙失败的那次，
   重试会掉进 AP 分支、又没有热点名（Android 侧只给前缀会被拒 `hotspot_ssid_required`），
   用户点下去得到的是**另一个**失败，排查方向直接被带偏。现在 `bleUuid` / `hotspotSsid` /
   `deviceNetworks` 一并带回，重试走的就是刚才那条。
2. **新增「改用热点方式配网」**（只在蓝牙失败时出现）：回搜索页并带
   `preferHotspot: true`，那一轮不再开 BLE、直接列 Wi-Fi 热点走 AP。

**为什么不做成自动回落**：自动重试要再等一轮超时（最长又是两分钟），而且 AP 必然弹一次
系统入网授权框——在用户以为已经结束的时刻突然冒出来，比多点一下更糟。把选择权交回去、
代价写在按钮上。

**EZ 不进优选池**：真机实测这台设备不支持，整条路 2026-09-11 已删。所以本产品的「自动
优选」实际是 BLE ⇄ AP 两选一。

**证伪记录（重要，别再有人接回来）**：过程中拿到过一段示例代码——
`ActivatorService.activator(ActivatorMode.BLE)` / `ActivatorService.discovery(DiscoveryMode.BLE)`
/ `BLEActivator` / `IDiscovery`。用 `tools/aar_class_dump.py` 把 7.5.1 能下到的模块全扫了一遍，
**这五个名字 0 命中**。那套命名属于**设备固件侧的 TuyaOS（TKL）**，不是 Android App SDK
（同一段话里「适配 TuyaOS Kernel Layer」也印证了这点）。App 侧只有两个 BLE 配网入口：
`IBleActivator`（纯蓝牙设备，`BleActivatorBean` **没有 ssid/pwd**）与
`IMultiModeActivator`（Wi-Fi+BLE 双模，`MultiModeActivatorBean` 带 ssid/pwd/token）——
花盆要连路由器，所以是后者。

### 4.1 桥接与状态层（**与 Wi-Fi 并行，AP 作为回落保留**）

原生（`MainActivity.kt`，沿用反射风格，**没有新增任何 gradle 依赖**——蓝牙模块本来就在
`thingsmart 7.5.1` 伞包的依赖里）：

- `bleProbe` → `getBleOperator().isBleSupported()/isBluetoothOpened()`，
  **三种不可用分开报**（包里没模块 / 手机没硬件 / 蓝牙没开）；
- `startBleScan` → `LeScanSetting.Builder().setTimeout(ms).setRepeatFilter(false)
  .addScanType(ScanType.SINGLE).build()` + `startLeScan(setting, ThingBleScanResponse)`，
  扫到的设备**逐台**从事件通道推给 Dart（`type = bleDevice`），不攒到扫完；
- `stopBleScan` → `stopLeScan()`，并接进 `releaseDeviceListeners()`；
- `queryDeviceConfigState` → `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder,
  IThingResultCallback)`；
- `pairBleDevice` → `IMultiModeActivator.startActivator(MultiModeActivatorBean,
  IMultiModeActivatorListener)`，`stopActivator(uuid)` 接进 `releasePairing`。

⚠️ **扫到的 `ScanDeviceBean` 必须留在原生侧**（`bleScanned: ConcurrentHashMap<String, Any>`）：
双模那两个 API 吃的都是这个对象本身，而它过不了方法通道（里面有 `byte[] raw` 这些广播原文）。
Dart 侧只拿 uuid，用的时候回原生取。**停扫时不清这张表**——用户点完设备页面就停扫，紧接着
要用那个 bean 去查列表、去配网。

`supportWifiList` 取自 `CombosFlagCapability.isCapabilityEnable(bean.getFlag(),
CombosFlagCapability.SCAN_WIFI)`——就是「固件 ≥ TuyaOS 3.6.1 才有」的那一位。**读不到
常量时按 false 报**：宁可回落到 Wi-Fi 扫描，也不要拿一个猜出来的能力位调下去让用户等
一次超时。

权限：BLE 走的是另一套（Android 12+ `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`，11 及以下
`ACCESS_FINE_LOCATION`），清单里四条早就声明好了、`BLUETOOTH_SCAN` 带 `neverForLocation`
所以 12+ 不再要定位。权限被拒的报错从「配网需要定位或附近 Wi-Fi 设备权限」改成**列出具体
是哪一条**。

Dart：`BleAvailability` / `BleDevice` / `DeviceWifiNetwork` 三个模型，仓库五个方法 +
`bleDevices` 流，状态层 `probeBle` / `startBleDiscovery` / `stopBleDiscovery` /
`loadDeviceWifiList`（**都不占 `_guard` 的 busy 锁**，理由与 `probeWifi` 相同）+
`pairViaBle`。`bleDevices` 按 uuid 去重、信号强的在前、**已绑定的不列**。

`_pairInternal` / `_pairOrRecover` 改成收一个「把凭据发出去」的函数：AP 传
`_repository.pair(...)`，双模传 `_repository.pairBleDevice(...)`。收尾（置第三步、作废
一次性令牌、并进设备列表、云端回查）两条完全共用——复制一份最容易在其中一份上漏掉作废令牌。

UI：搜索页的「已发现设备」列表改吃统一模型 `_FoundDevice`（BLE / 热点两种来源同一种行），
行上标明来源与下一步；蓝牙不可用时页面上多一行说明（关着蓝牙 = 少了主路径，用户只会觉得
「搜得慢」）。「连接 Wi-Fi」页新增 `bleUuid` / `deviceNetworks` 两个参数：前者决定配网走
`pairViaBle` 还是 `pairViaHotspot`，后者让「切换」弹层直接列**设备自己扫到的**网络。
走双模时本页那几处「把手机 Wi-Fi 还回去」全部跳过——手机从来没离开过路由器。

## 关键决策

- **双模是主路径，AP 是回落。** 固件方确认支持蓝牙配网之后定的。AP 那条**完整保留**、
  代码一行没删：手机蓝牙关着、设备不是双模、或 BLE 一台都没扫到时自动走它。
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
2. **双模整条未真机验证**，三条硬风险：① 反射签名虽已解包核对，但**参数装箱与运行时行为
   没有编译期保护**；② `queryDeviceConfigState` 的回调泛型是推的（已把每项 `toString()`
   原样带回 `raw` 字段，真机一眼能看出是什么 bean）；③ `MultiModeActivatorBean` 是公有
   裸字段、靠 `Field.set` 写，字段名写错不会编译报错、只会在运行时 `NoSuchFieldException`。
3. `setTimeOut` 仍是 120 秒（官方建议 60），本轮有意没动。
4. 手动热点回落（`hotspot_manual_required`）在状态层还留着（iOS / Android 9 唯一的路），
   但**配网页已经不认它了**，会直接进失败页显示那段引导文案。产品口径是「不再考虑
   Android 9 及以下」，iOS 侧尚未决策。

## 回滚或恢复

- 只回滚双模、回到纯 AP：把 `_foundDevices` 改成永远返回 Wi-Fi 热点那份即可——一行。
  这样 BLE 既不发现也不配网，动线回到 2026-09-11 上午那版；其余代码留着不碍事。
  彻底删则是：`MainActivity.kt` 的「BLE 发现」整节与分发表五行、Dart 三个模型、仓库五方法、
  状态层那一节与 `pairViaBle`、搜索页 `_FoundDevice` 相关、配网页 `bleUuid`/`deviceNetworks`。
- 卡住那条修复**不要回滚**。
