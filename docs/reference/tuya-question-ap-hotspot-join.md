# 给涂鸦的提问：AP 配网中「手机连接设备热点」这一步，在 Android 10 上到底该怎么做

> 这是一份**发给涂鸦技术支持/AI 助手**的问题稿。诉求只有一个：**请给出可核对的类全名 +
> 方法签名 + 所在 artifact**，我们会拆 AAR 核对。

---

## 一、环境

| 项 | 值 |
| --- | --- |
| SDK | `com.thingclips.smart:thingsmart:7.5.1` + `com.thingclips.smart:thingsmart-expansion-sdk:7.8.0` |
| App 技术栈 | Flutter，Android 侧用 Kotlin + MethodChannel 桥接（反射调用 SDK） |
| 手机 | **Android 10**（API 29），非系统应用、非预装、无 root |
| `minSdk` | 24 |
| 设备 | 智能花盆，固件 > 3.6.1，涂鸦标准 **AP 热点配网（AP-cfg）**，热点名 `SmartLife-xxxx`（开放网络，无密码） |
| 已声明权限 | `INTERNET`、`ACCESS_NETWORK_STATE`、`CHANGE_NETWORK_STATE`、`ACCESS_WIFI_STATE`、`CHANGE_WIFI_STATE`、`CHANGE_WIFI_MULTICAST_STATE`、`NEARBY_WIFI_DEVICES`、`ACCESS_COARSE_LOCATION`、`ACCESS_FINE_LOCATION` |

**产品硬性要求：整个配网流程中不要出现系统的入网授权框**（「要与智能花盆搭配使用的设备 /
取消 / 连接」那个框）。这是提问的全部起因。

---

## 二、我们按你们的建议试过的三条路，以及真机结果

### 路 1：`WifiManager#connect()` 静默连接 —— ❌ 不通

你们的原话是「智能生活 App 不弹系统 Wi-Fi 连接框，是因为它采用了 Android 10+ 的
`WifiManager#connect()` 静默连接方案」。我们按这条实现了，反射调用
`WifiManager.connect(WifiConfiguration, ActionListener)`，真机日志（每一秒打一行当前 SSID）：

```
connect(WifiConfiguration,ActionListener) 存在，调用
已交给系统，开始等关联（当前「ChinaNet-duu」）      ← ChinaNet-duu 是路由器
0s 当前「ChinaNet-duu」
1s 当前「ChinaNet-duu」
…
11s 当前「ChinaNet-duu」
等了 12194ms 还在「ChinaNet-duu」
addNetwork 返回 -1
```

三件事同时成立：

1. 该方法在这台手机的 `WifiManager` 上**确实存在**（反射找得到），调用**不抛异常**；
2. 我们注册了**真实的 `ActionListener`**，但 `onSuccess()` 和 `onFailure(reason)`
   **一个都没有回调**——请求被系统静默丢弃；
3. `WifiManager.addNetwork(config)` 返回 **-1**，即系统拒绝让本应用保存网络。

我们的理解：`WifiManager#connect()` 是 `@SystemApi`，需要 `NETWORK_SETTINGS` 或
`NETWORK_SETUP_WIZARD`（`signature|privileged`），第三方应用拿不到。

### 路 2：`WifiNetworkSuggestion` —— 机制上不满足「按需立刻连」

`addNetworkSuggestions()` 是「把凭据交给平台，由平台自行决定何时连」，没有任何 API 能要求
它**立刻**连某一条；而设备热点**没有外网**，手机正连着有外网的路由器，平台大概率不会切。
另外首次调用还会弹系统通知征求「允许本应用建议网络」。我们已按产品要求实现并会继续实测，
但希望你们确认机制上的判断。

### 路 3：`WifiNetworkSpecifier` + `requestNetwork` —— ✅ 能连上，但**必弹系统框**

这是我们**唯一真正能连上设备热点**的方式，也是 git 历史上配网成功的那一版所用的方式。
代价是 Android 10+ 强制弹一次入网授权框，App 关不掉、不能代点、不能改样式。

---

## 三、我们从你们官方文档里读到的、互相矛盾的两句话

1. Android AP 配网文档开头：「…… **但用户需要手动切换手机的 Wi-Fi 设置**。」
2. 同一篇「热点配网新流程」一节：「在配网过程中，**SDK 会在指定时间内自动去连接 AP 热点**,
   如果连上后，SDK 内部会去获取设备状态，上报给业务方。**只针对新设备固件有效。**」
3. iOS 业务拓展 SDK 文档的时序图里写的是：`App → 引导用户连接到设备热点`。

所以「谁来连热点」在文档里有三种说法。**第 2 条是我们最关心的。**

---

## 四、请逐条回答（每条都请给可核对的类全名 + 方法签名 + artifact）

1. **`WifiManager#connect()` 那条建议，对"第三方非系统应用"是否成立？** 如果成立，请说明
   在 Android 10 上需要哪些权限/声明；如果不成立，请确认撤回这条建议。

2. **「SDK 会在指定时间内自动去连接 AP 热点」具体是哪个 API、走哪条调用链？**
   - 是 `ThingHomeSdk.getActivatorInstance().newOptimizedActivator(ThingApActivatorBuilder)`
     + `queryDeviceConfigState(ApQueryBuilder, callback)` 吗？
   - 它内部用的是 `WifiNetworkSpecifier`（会弹框）还是别的机制（不弹框）？
   - **"只针对新设备固件有效"的门槛是什么版本？** 我们的固件 > 3.6.1，够不够？
     有没有 API 能让 App 提前判断"这台设备支持不支持 SDK 自连热点"？

3. **`ThingActivatorCoreKit`（扩展 SDK）那条链会不会自己连热点？**
   我们已按文档接上了
   `ThingActivatorCoreKit.getActiveManager().newThingActiveManager().startActive(ThingDeviceActiveBuilder)`,
   `setActiveModel(ThingDeviceActiveModeEnum.AP)`。请确认：**调用方需不需要先把手机连到设备
   热点上？** 如果需要，那"不弹框"就仍然无解，请直说。

4. **智能生活 App 在 Android 10 上到底是怎么连上 `SmartLife-xxxx` 热点的？**
   智能生活同样是第三方应用（不是系统预装），所以它不可能有 `NETWORK_SETTINGS`。
   请给出它实际走的机制：
   - (a) 它其实**也弹**了 `WifiNetworkSpecifier` 的框，只是截图里没拍到？
   - (b) 它走的是「SDK 自连 + 新固件」那条路？
   - (c) 它引导用户自己去系统 Wi-Fi 设置里连？
   - (d) 其它——请具体说明。

5. **如果以上都不能做到"零系统框"，请明确告知。** 我们会据此改产品口径（把授权框收到
   某一个按钮上），不再继续试。**我们需要的是结论，不是可能性。**

---

## 五、一个请求：请只给能核对的 API

之前的沟通里出现过 4 个**经查不存在**的 API，每次都让我们白写一轮代码：

| 给过的说法 | 核查结果 |
| --- | --- |
| `ThingSmartHotspotCredentialKit` | 不存在 |
| `WifiManager#connect()` 可静默连任意热点 | 是 `@SystemApi`，需 `NETWORK_SETTINGS` |
| `IThingOptimizedActivator.startAPConfig(ApHandlerBean, IThingResultCallback<DeviceBean>)` | 该接口没有此方法；`ApHandlerBean` 是 `resumeAPConfigWifi` 的参数 |
| `WifiManager#connectSta()` | Android 没有这个 API |
| 「`IThingOptimizedActivator` 本身不存在」 | 这条说法本身是错的——它就在官方 AP 文档的示例代码里 |

我们会把你们给的每个类名从 Maven 拉 AAR 拆包核对（`thingsmart-activator-core-kit` 就是这么
确认的）。**所以请附上：类全名、方法完整签名、所在 artifact 与版本。** 文档链接也请给具体
章节锚点。谢谢。
