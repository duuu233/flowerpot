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

---

## 五、补记（同日，拆包续查）：回调名字我一开始写错了

上面那版提交之后，把 AAR 又拆了一遍，逐个类核对方法名，发现 **通用回调代理漏了真正的
失败回调**——这是个会把错误整个吞掉的 bug，已修。

### `IThingDeviceActiveListener`（拆包实测方法名）

| 方法 | 参数 | 之前代理怎么处理 |
| --- | --- | --- |
| `onFind` | `String devId` | ❌ 落到 `else`，丢掉 |
| `onBind` | `String devId` | ❌ 落到 `else`，丢掉 |
| `onActiveSuccess` | `DeviceBean` | ✅ 已处理 |
| `onActiveError` | `ThingDeviceActiveErrorBean` | ❌ **落到 `else`，丢掉** |
| `onActiveLimited` | `ThingDeviceActiveLimitBean` | ❌ 落到 `else`，丢掉 |

通用代理只认 `onError` / `onFailure`，而这套叫 **`onActiveError`**。后果：配网失败时
原生那边什么都不上报，Dart 侧只能等自己的超时，页面上看到的还是一条没有成因的
「超时」——正是我们查了好几天的那种现象。

另外两个 bean **不是 `(code, msg)` 两个字符串**，按 String 取参也取不到东西：

- `ThingDeviceActiveErrorBean`：`getId` / `getErrCode` / `getErrMsg` / `isCanRetry` / `getMode`，
  且 `toString()` 自带全字段
- `ThingDeviceActiveLimitBean`：`getErrorCode` / `getErrorMsg` / `getName` / `getMac` / `getUuid` …
  （注意是 `error…` 不是 `err…`，两套名字都要试）

### 还补了「暂停」回调

`ThingDeviceActiveBuilder.setListener(...)` 的参数类型是 `IThingDeviceActiveListener`
（拆包确认只有这一个重载），而热点设备的暂停状态走它的子接口
`IThingDeviceStatePauseActiveListener.onActivatorStatePauseCallback(PauseStateData)`。
按官方文档，这个回调的含义是 **Wi-Fi 密码错误 / 设备连不上路由器**。

所以代理现在**同时实现这两个接口**（`callbackProxy` 加了 `extraTypes`），暂停也当失败
原文报出来，不兜底不重试。这条很可能就是当前失败的真实成因。

### 进度条改成按名字精确映射

`pairViaActivatorKit` 订阅 `pairingSteps`：`onFind` → 设备连路由器，`onBind` → 设备上线。
这一套的回调名是**确定的**，不用像 `pairViaDeviceHotspot` 那样靠到达顺序猜。

### 顺手校正一条自己的核实记录

`ThingDeviceActiveModeEnum` 里 **`AP` 和 `EZ` 确实存在**。差点误判成没有——`strings`
默认只打印 ≥4 字符的串，两字母枚举值被过滤了，要 `strings -n 2`。已写进
`PRODUCT_RULES.md` §5.1。

## 六、同日第 4 条外部说法：`IThingOptimizedActivator` 不存在？—— 这条是错的

该渠道又发来一条，说 `IThingOptimizedActivator` 和 `startAPConfig` **都**不存在，AP 唯一
标准流程是 `newActivator(ThingApActivatorBuilder)` + `activator.start()`。

逐条核：

| 说法 | 核实 |
| --- | --- |
| `startAPConfig` 不存在 | ✅ 对，这条和我们之前的结论一致 |
| `IThingOptimizedActivator` 不存在 | ❌ **错**。`docs/reference/tuya-ap-mode-android.md:129` 就是官方示例：`IThingOptimizedActivator mThingActivator = ThingHomeSdk.getActivatorInstance().newOptimizedActivator(builder);` |
| 「`queryDeviceConfigState` / `resumeAPConfigWifi` 是真接口」 | ✅ 对——但它们正是 `IThingOptimizedActivator` 的方法，所以这条回复**自相矛盾** |
| `activator.setListener(new IThingActivatorListener(){ onSuccess(IDevice) })` | ❌ 名字不对。官方两套文档里 listener 都是**设在 builder 上**（`ThingApActivatorBuilder.setListener`），接口是 `IThingSmartActivatorListener`，成功回调是 `onActiveSuccess(DeviceBean)`，没有 `IThingActivatorListener` / `IDevice` |

而它给的这套 `newActivator` + `start()` 正是我们仓里**早就有的** `pairViaHotspot`
（git 里最后配成过的那一版）。也就是说：这条回复既没有给出新东西，也**没有回答唯一的
那个问题**——

> **谁把手机连到设备热点上？**

官方文档自己把话说得很清楚：

- Home SDK AP 文档开头（`tuya-ap-mode-android.md:2`）：「…**用户需要手动切换手机的
  Wi-Fi 设置**」
- 同文档新流程一节（:216）：「在配网过程中，SDK 会在指定时间内自动去连接 AP 热点 …
  **只针对新设备固件有效**」
- iOS 业务拓展文档的时序图（`tuya-ios-ap.md`）：`app ->> app: 引导用户连接到设备热点`

⇒ **只有「新流程 + 新固件」这一条路上 SDK 会自己连热点**；经典 AP 流程里连热点是
App/用户的事。这也解释了为什么「不弹系统框」这么难——要么指望 SDK 自己连（新固件），
要么就得碰 `WifiNetworkSpecifier`（必弹）。下次问涂鸦就只问这一句：
**我们这台设备的固件，`queryDeviceConfigState` 会不会自己连热点？**
