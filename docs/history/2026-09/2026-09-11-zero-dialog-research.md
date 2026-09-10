# 2026-09-11 「有没有永远不弹系统框的配网流程」——查证结论

## 产品问题

> 就没有永远不弹出系统框的配网流程吗？可以参考智能生活 APP 的配网流程，或者再去找找
> 涂鸦 SDK 文档查查。
>
> 流程就是 1.自动搜索设备，把搜索的设备展示到列表 2.点击要配网的设备的连接按钮，然后开始
> 输入 WIFI 密码，这里也可以切换 WIFI，然后点击确认配网，流程就完了，没有多余的操作。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`。本轮**只查证与记录，无代码改动**。

## 一、产品要的流程就是现在的实现

「搜索列表 → 点「连接」→ 输/切 Wi-Fi 密码 → 确认配网」——结构上与当前实现一致
（见 `docs/PRODUCT_RULES.md` 1.4）。**唯一的侵入是第 2 步那一次系统确认框。**

## 二、Android 侧：没有任何 API 能静默连上指定热点（已查到底）

此前已确认 `WifiNetworkSpecifier` 必弹框、`addNetwork`/`enableNetwork` 对
targetSdk ≥ 29 always fail。本轮把最后一条候选查清：

### `WifiNetworkSuggestion`（"只授权一次、之后静默"）——不可用

Android 官方文档（`develop/connectivity/wifi/wifi-suggest`）原文：

> Immediately after the app places a suggestion for the first time, the user is notified.
> **On Android 11 (API level 30) and higher, the user sees a dialog if the app is running in
> the foreground**, and a notification if the app is running in the background.

> **The platform ultimately chooses which access point to accept** based on the input from
> your app and others.

两条都致命：

1. 首次在前台**仍然是一个对话框**，并没有省掉；
2. **应用无法强制立刻连上某个指定网络**——平台自己决定何时连、连哪个。而配网要的是
   "此刻就连上这个**没有互联网**的热点"，Android 恰恰倾向于不切到没有互联网的网络。

⇒ 这条路不适用于 AP 配网。

### 另外排除过的

- `CompanionDeviceManager` + `WifiDeviceFilter`：它本身就是一个**系统设备选择弹窗**，
  而且关联之后并不授予静默连 Wi-Fi 的能力。
- 降 `targetSdkVersion` 到 28：Google Play 早已要求 33+，且属于产品+安全级决策，不可行。

## 三、涂鸦文档侧：对 Android 10+ 的限制一字未提

- 「设备配网 UI 业务包」（`deviceconfiguration?id=Ka8qhzk488zyd`）只给定义，**不说明连热点
  的实现机制**，也没提 `WifiNetworkSpecifier` / `WifiNetworkSuggestion` / 系统限制。
- 「设备配网」（`activitor?id=Ka5vox88n9csq`）同样未涉及 Android 权限限制。
- 而涂鸦对 AP 模式的**定义原话**反而是：「成功率高、可靠性好……**但用户需要手动切换手机的
  Wi-Fi 设置**」——也就是涂鸦自己的 AP 标准流程比我们现在这个**多一步**（把用户送去系统
  Wi-Fi），不是少一步。

⇒ 指望涂鸦文档给出"零弹框连热点"的 API，没有。

## 四、真正的零弹框答案在**设备端**：EZ / SmartConfig（快连）

**EZ 模式下手机全程留在路由器上**，App 把凭据以 802.11 报文广播出去，**根本不需要连接设备
热点**。没有热点连接 ⇒ 没有任何系统 UI ⇒ 全程零弹框。这是唯一真正"永远不弹框"的配网方式。

产品此前的口径是「永远不考虑 EZ，设备不支持」。但设备开发的原话是：

> 设备采用涂鸦标准 AP 热点配网（AP-cfg），**没使用** EZ/SmartConfig 快连

**「没使用」和「不能用」是两件事。** 涂鸦 Wi-Fi 模组通常两种都支持，由固件配置决定启用哪些。

### 待确认（设备团队）

**固件能否同时开启 EZ/快连？** 能的话，流程就完全是产品要的样子，且全程零系统 UI。
桥接层里 EZ 那条路的代码仍在（当前是死代码：Android `EZ_MODE_NAMES`、
iOS `ThingActivatorModeEZ`），启用只是换 `PairingRequest.mode`。

⚠️ **不擅自切过去**——产品明确说过不考虑 EZ，这是设备团队要先回答的问题。

## 五、在那之前，唯一能把框降到零的办法

让用户在**系统设置**里手动连一次该热点。系统会把它存进「已保存的网络」，之后设备一开机
手机自动重连，我们的代码检测到「已经在目标热点上」**全程跳过**，一次框都不弹。
这也最可能是产品记忆中「以前都不弹框」的真相。

⚠️ 我们自己用 `WifiNetworkSpecifier` 连上的那次**不会**被系统保存（进程专属的一次性连接），
所以靠 App 连永远不会变成「记住了」。

## 结论一句话

App 侧已经到顶了：框只剩一次、只在「连接」按钮那一刻。再往下**只有两条路**——
① 设备固件开 EZ（零框，需设备团队确认）；② 让用户在系统设置里连一次热点（此后零框）。
