# 2026-09-11 接入扩展 SDK 的 `ThingActivatorCoreKit`；并拆穿一条编造的 API

## 一、涂鸦两条回复，一真一假——都拆包核实过

产品先后转来两条涂鸦回复。**核实方式和上次一样：从 Maven 下 AAR、解包、看类和方法。**

### ✅ 真的：「Flutter 场景下必须使用 `ThingActivatorCoreKit`」

拆包结果（`maven-other.tuya.com` → `thingsmart-expansion-sdk-7.8.0.pom` →
`thingsmart-activator-core-kit-7.8.0.aar`）：

| 类 / 方法 | 存在？ |
| --- | --- |
| `com.thingclips.smart.activator.core.kit.ThingActivatorCoreKit` | ✅ 有 `getActiveManager` |
| `…kit.inter.IThingActivator` | ✅ 有 `newThingActiveManager` |
| `…kit.active.inter.IThingActiveManager` | ✅ 有 `startActive` / `stopActive` |
| `…kit.builder.ThingDeviceActiveBuilder` | ✅ `setActiveModel/setContext/setSsid/setPassword/setToken/setTimeOut/setSecurityConfig/setListener` |
| `…kit.constant.ThingDeviceActiveModeEnum` | ✅ 含 **`AP`** 与 **`EZ`** |
| `…kit.ThingActivatorDeviceCoreKit` | ✅ 取令牌用 |

**而且 `thingsmart-expansion-sdk:7.8.0` 本来就在我们的 `build.gradle.kts` 里**，
`thingsmart-activator-core-kit` 是它的传递依赖——不用加任何依赖。

### ❌ 假的：`IThingOptimizedActivator.startAPConfig(...)` + `WifiManager#connectSta()`

同一渠道随后给的"完整调用链"经查是编造的：

| 说法 | 核查 |
| --- | --- |
| `IThingOptimizedActivator.startAPConfig(ApHandlerBean, IThingResultCallback<DeviceBean>)` | **不存在**。存档的官方文档里该接口只有 `queryDeviceConfigState` / `startActivator` / `resumeAPConfigWifi` / `stopActivator` / `onDestroy`；`startAPConfig` 出现 **0 次** |
| `ApHandlerBean` 是 `startAPConfig` 的参数 | 错。它是 **`resumeAPConfigWifi`（恢复配网）** 的参数 |
| SDK 内部用 `WifiManager#connectSta()` | Android **没有这个 API** |

这是该渠道第 **3** 次给出不存在的 API（前两次：`ThingSmartHotspotCredentialKit`、
`WifiManager#connect()` 静默连接）。

⇒ **规矩：任何来自该渠道的新 API，先拆包核实再写代码。**

## 二、改动：接入 `ThingActivatorCoreKit`

### 原生 `MainActivity.kt`

新增 `activeStart` / `activeStop`：

```
ThingActivatorCoreKit（Kotlin object，先取 INSTANCE 字段、再退到 getInstance()）
  → getActiveManager() → IThingActivator
  → newThingActiveManager() → IThingActiveManager
ThingDeviceActiveBuilder：setActiveModel(ThingDeviceActiveModeEnum.AP) / setContext /
  setSsid / setPassword / setToken / setTimeOut(**秒**) / setSecurityConfig / setListener
  → manager.startActive(builder)
```

⚠️ 这个 builder 的 `setTimeOut` 单位是**秒**，与 `ApActivatorBuilder` 的毫秒不同。
令牌沿用现有的 `freshActivatorToken()` / `fetchActivatorToken`；安全配置沿用预取的
`deviceSecurityConfig`。每一步都 `trace()`（会打到页面上）。

### Dart

- `TuyaRepository.activeStart({mode, ssid, password, timeout})` / `activeStop()`；mock 同步补上
  （mock 里直接复用 `pair()`，所以既有用例不受影响）。
- `FlowerpotState.pairViaActivatorKit({ssid, password, mode = 'ap'})`，失败复用
  `_connectDiagnostic()`（原文 + 用时 + 手机当时连的网络），日志照样进页面。
- 「连接 Wi-Fi」页的配网调用换成它。

### 三套实现并存，切换只改一处调用点

| 路径 | 入口 | 备注 |
| --- | --- | --- |
| **扩展 SDK（当前）** | `pairViaActivatorKit` | 涂鸦回复指定；本次新接 |
| Home SDK 新流程 | `pairViaDeviceHotspot` | `queryDeviceConfigState` + `startActivator` |
| Home SDK 原流程 | `pairViaHotspot` | git 里最后一版配成过的（含 `WifiNetworkSpecifier`） |

调用点的注释写了怎么切。

## 三、验证

**未验证。** 本机没有 Kotlin/Dart 工具链。已做的静态核实：

1. **类与方法从 AAR 实拆确认**（上表），不是照文档抄的。
2. 四个改动文件括号配平，`state.dart` / `MainActivity.kt` 与 HEAD 同基线。
3. `activeStart` / `activeStop` 在抽象、实现、mock 三处齐全。
4. 没有引入新语法糖。

## 四、这一版要看什么

页面上的日志框会给出：

```
active: begin mode=AP, wifi=TP-LINK_2.4G
active: manager=XxxActiveManager
active: builder ready, starting …
active: handed to kit, waiting for callback
active: success|error … , wifi now = ?
```

**重点仍是 `wifi now`**：如果配网过程中它变成了 `SmartLife-…`，说明这套 kit 确实会自己
连热点——那就是我们找了很久的答案；如果始终是路由器名，说明它同样不连，问题回到
「谁来连热点」上。
