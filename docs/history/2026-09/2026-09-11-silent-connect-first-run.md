# 2026-09-11 真机第一次跑静默连接：方法存在、调用不抛、手机没动

## 一、真机日志（产品截图）

```
join: WifiManager.connect() exists, invoking
join: silent connect failed → connect() 调用成功但 2.5 秒内没连上（当前：ChinaNet-duu）
【hotspot_join_failed】connect() 调用成功但 2.5 秒内没连上（当前：ChinaNet-duu）
```

三件事同时成立：

1. `WifiManager` 上**真的有** `connect(WifiConfiguration, ActionListener)`——反射找到了；
2. 反射调用**没抛异常**（没有 `SecurityException`、没有 `NoSuchMethodException`）；
3. 手机**一直没离开路由器** `ChinaNet-duu`。

## 二、这个结果其实什么都没证明——我的探针有两个洞

### 洞 1：`ActionListener` 传的是 `null`

```kotlin
method.invoke(wifi, config, null)   // ← 旧代码
```

`ActionListener` 是**唯一**能区分「系统受理了」和「系统把请求丢了」的信号：
`onSuccess()` / `onFailure(reason)`，reason 只有三个值 `ERROR=0` / `IN_PROGRESS=1` /
`BUSY=2`。传 null 等于把这条信号扔掉，于是「不抛异常」被我当成了「调用成功」——
**它只说明本地那一跳没报错，跨进程那一侧怎么处理的，我们一无所知。**

### 洞 2：只等 2.5 秒，而且在主线程上等

Wi-Fi 关联本身就要三到十秒。2.5 秒这个上限是为了躲 ANR（主线程阻塞 5 秒）才取的，
**根本等不到结论**。所以"2.5 秒内没连上"既可能是被系统拒了，也可能只是还没连完。

## 三、改法

- **注册真的 `ActionListener`**（类型从 `method.parameterTypes[1]` 取，不写死类名），
  `onSuccess` / `onFailure(reason=… ERROR|IN_PROGRESS|BUSY)` 都打到页面上。
- **等待改成 `Handler` 轮询**，不阻塞线程，上限提到 **12 秒**，每跨一秒打一行当前 SSID
  ——从截图就能看出手机有没有动过。
- **失败后加一把 `addNetwork()` 探针**：Android 10+ 对没有 `NETWORK_SETTINGS` 的普通应用，
  这个方法固定返回 **-1**。拿到 -1 就是「本应用没有特权、这条路在这台手机上走不通」的
  铁证，比一次超时有说服力得多。若意外返回 ≥0，就接着 `enableNetwork(netId, true)` 再等
  10 秒（这仍然是静默连接，不弹框，不违反口径），完事 `removeNetwork` 收拾掉。
- 全过程拼成一条证据链当错误文案返回，页面直接显示。仍然**不兜底**：不退回
  `WifiNetworkSpecifier`。

Dart 侧 `hotspotJoinDeadline` 是 90 秒，native 最坏 22 秒，够。

## 四、下一次截图要看什么

按可能性从高到低，三种结果对应三个不同结论：

| 日志 | 结论 |
| --- | --- |
| `ActionListener.onFailure(reason=0 ERROR)` + `addNetwork 返回 -1` | **静默连接这条路死了。** 普通应用没有 `NETWORK_SETTINGS`，涂鸦说的「智能生活用 `WifiManager#connect()`」对第三方 App 不成立。剩下两条路：指望 SDK 自己连热点（要新固件，见 `tuya-ap-mode-android.md:216`），或者接受 `WifiNetworkSpecifier` 的系统框 |
| 收不到任何 `ActionListener` 回调，12 秒后还在路由器 | 请求被静默丢弃，结论同上，但证据弱一些——`addNetwork` 的返回值是关键 |
| `onSuccess` + 某一秒 SSID 变成 `SmartLife-xxxx` | **这条路通**，之前只是等得不够久（2.5 秒太短）。那就把配网接在这后面 |

---

## 五、第二次真机：结论出来了，静默连接这条路死了

```
join: connect(WifiConfiguration,ActionListener) 存在，调用
join: 已交给系统，开始等关联（当前「ChinaNet-duu」）
join: 0s  当前「ChinaNet-duu」
…（逐秒，一行不落）…
join: 11s 当前「ChinaNet-duu」
join: 等了 12194ms 还在「ChinaNet-duu」
join: addNetwork 返回 -1（-1 = 系统拒绝保存网络，本应用没有 NETWORK_SETTINGS 特权）
```

三条一起看，结论是确定的，不是推断：

1. `WifiManager.connect(WifiConfiguration, ActionListener)` 在这台手机上**存在**，反射
   调用**不抛异常**；
2. **`ActionListener` 一个回调都没来**——`onSuccess` 没有，`onFailure` 也没有。请求被系统
   静默丢掉了（这正是上一版传 `null` 看不出来的那件事）；
3. `addNetwork()` 返回 **-1**，系统拒绝让本应用保存网络。

⇒ **本应用没有 `NETWORK_SETTINGS`（signature|privileged）特权，涂鸦那句「智能生活用
`WifiManager#connect()` 静默连接、系统不弹框」对第三方应用不成立。**

`trySilentConnect` / `silentConnect` 两版探针的代码都已删掉（结论已拿到，留着就是死代码，
要看实现去 `e861aff`、`ec6a7f0`）。

## 六、产品指定用 `WifiNetworkSuggestion`（「我是安卓 10 就用这种」）——已实现

### 它和 `Specifier` 根本不是一回事

| | `WifiNetworkSpecifier` | `WifiNetworkSuggestion` |
| --- | --- | --- |
| 语义 | 「**现在**给我连这个网络」 | 「凭据给你，**你觉得合适就连**」 |
| 系统 UI | 必弹入网授权框，关不掉 | 不弹授权框；但**首次**会发通知问「是否允许本应用建议网络」 |
| 何时连上 | 用户点「连接」后立刻 | 平台判定它是**当前最优网络**时才自动连，**没有 API 能要求它立刻连** |
| 能连没外网的热点吗 | 能（`removeCapability(NET_CAPABILITY_INTERNET)`） | 悬——手机正连着有外网的路由器，系统评分里"已验证外网"权重很高 |

所以我的判断是它很可能连不上设备热点。**但这是推断，产品要求就按这个实现，结论交给真机。**
实现上两条路按顺序走，建议连不上就干净让位给 `Specifier`：

1. `WifiNetworkSuggestion.Builder().setSsid(target).setIsAppInteractionRequired(true)`
   （设备热点是开放网络，不设 passphrase）；
2. `addNetworkSuggestions` 的**状态码打到页面上**，并翻成人话：
   `0 SUCCESS` / `2 ERROR_APP_DISALLOWED（用户没允许本应用建议网络）` / `3 ERROR_ADD_DUPLICATE` …；
3. 状态码为 0 就等 **20 秒**，`Handler` 轮询不阻塞线程，**每跨一秒打一行当前 SSID**；
4. 连上 ⇒ 成功，全程没有入网授权框；20 秒没连上 ⇒ 撤掉建议，走 `Specifier`。

### 撤销是必须的

`WifiNetworkSuggestion` 是**进程外状态**。不撤，用户退出 App 之后系统还会继续往这条没有
外网的热点上连——直接违反 §1.4.1「无论怎么退出，都要把手机的 Wi-Fi 还回去」。所以
`releaseHotspotRequest()` 里统一 `removeNetworkSuggestions`，并且把当初那个 suggestion
对象留着精确撤销（`minSdk = 24`，字段声明成 `Any?`，用的时候在 `SDK_INT >= Q` 分支里强转）。

### 下一次截图看这一行

```
join: addNetworkSuggestions → ? ?
```

- `→ 0 SUCCESS` 然后某一秒 SSID 变成 `SmartLife-xxxx`：**这条路通，零系统框**，`Specifier`
  从此只当兜底。
- `→ 0 SUCCESS` 但 20 秒 SSID 一直是 `ChinaNet-duu`：平台不肯切（就是上面表格里那个"悬"），
  只能接受 `Specifier` 的一次授权框。
- `→ 2 ERROR_APP_DISALLOWED`：通知栏里有一条「允许花盆建议 Wi-Fi 网络？」没点允许。点了再试。

---

## 七、第三次真机：`Suggestion` 没连上，走了 `Specifier`，系统框照旧

产品反馈：「我刚才测试了这个版本还是走的兜底 弹出系统框了」。

**这是机制决定的，不是实现漏了什么。** 官方指南
（`developer.android.com/develop/connectivity/wifi/wifi-suggest`）两句话就解释完了：

1. 「Immediately after the app places a suggestion for the first time, the user is notified.
   … On **Android 10 (API level 29), the user sees a notification**, regardless of whether the
   app is running in the foreground or the background.」

   ⇒ **首次放建议必须由用户在通知栏点同意。** 没点，这条建议就是摆设——而
   `addNetworkSuggestions()` **照样返回 0（SUCCESS）**，`ERROR_APP_DISALLOWED(2)` 只在用户
   明确拒绝过之后才返回。所以"返回 0"根本不能当成"平台会连"。

2. 「The platform **ultimately chooses** which access point to accept based on the input from
   your app and others.」

   ⇒ 平台自己挑，**没有任何 API 能要求它立刻连某一条**。而设备热点**没有外网**，手机正连着
   有外网的路由器——按 Android 的网络评分，它基本不会切过去。

⇒ **`WifiNetworkSuggestion` 不适合"按需连一个没有外网的指定热点"这件事。** 它是为"用户将来
会遇到这个网络，凭据先给你"设计的（运营商 Wi-Fi、酒店），不是为配网设计的。

### 这一轮改了三处

1. **等待从 20 秒压到 10 秒。** 原来那 20 秒是纯烧配网窗口——设备静置会退出配网模式
   （§1.5），而多等 10 秒并不会让一个"平台不打算连"的建议变成连上。
2. **去掉 `setIsAppInteractionRequired(true)`。** 官方指南标的是
   「Optional (Needs location permission)」，不是连接的必要条件，加了只多一种失败方式。
3. **失败那行日志写清下一步**：通知栏里若有「允许本应用建议 Wi-Fi 网络？」请点允许后重试；
   点过仍不连，就是平台不肯从有外网的路由器切到没外网的热点，App 无法干预。

### 还剩两条路，都要产品拍板

| 方案 | 系统 UI | 代价 |
| --- | --- | --- |
| **维持现状**：`Specifier` 的一次授权框，收在「连接」按钮上（§1.2） | 一次，点一下 | 产品已经接受过这个口径；**这是目前唯一能配成的路** |
| **SDK 自连热点**：`queryDeviceConfigState`（`tuya-ap-mode-android.md:216`，「只针对新设备固件有效」） | 未知——SDK 内部若也用 `Specifier` 就照样弹 | 要涂鸦回答固件门槛；见 `docs/reference/tuya-question-ap-hotspot-join.md` 第 2 问 |

**不建议再花时间在 `Suggestion` 上。**

---

## 八、结案：涂鸦官方书面确认「零系统框」不可行

2026-09-11 涂鸦回复（全文见 `docs/reference/tuya-question-ap-hotspot-join.md` 末尾）：

1. Android 10+ 第三方 App **无法**用 `WifiManager#connect()` 静默连接（需 `NETWORK_SETTINGS`,
   **不可申请**）——和我们的真机判定一致（`addNetwork` 返回 -1）；
2. **`WifiNetworkSpecifier + requestNetwork()` 是唯一可行路径**，系统授权框**无绕过方案**；
3. 「SDK 自动连热点」仅适用于 TuyaOS ≥ 3.6.1 固件 + **智能生活 App（预置/白名单应用）**；
4. 文档里「SDK 会在指定时间内自动连接」指的是**设备端行为**，**不是手机侧静默连接**。

### 第 4 条就是 `223bdae` 返工的根因

我们当时把那句话读成了"手机侧 SDK 会自己连热点"，于是删掉了连热点这一步，之后全是 `207220`
整体超时，来回折腾了好几天。**这句话说的是设备端。** 已写进 `PRODUCT_RULES` §4.0 置顶。

### 第 3 条解释了为什么照抄智能生活不成立

它是预置/白名单应用。「智能生活不弹框」这个观察对第三方 App **不是可复制的目标**。

### 这一轮的代码动作

- **删掉 `WifiNetworkSuggestion` 整条路**（`suggestHotspot` / `suggestionStatusName` /
  `awaitSsid` / 两个字段 / `removeHotspotSuggestions` / import）。留着只会在配网关键路径上
  白等十秒，而设备静置就会退出配网模式（§1.5）——**直接降低配网成功率**。实现要找回去
  git `747d871`。
- `joinDeviceHotspot` 现在直接 `joinViaSpecifier(...)`，并把涂鸦那四条原文抄在调用点上方，
  后面谁再想"优化掉"这一步，先读那段注释。

### 剩下的唯一可做的事：把这一次授权框做得不突兀

涂鸦的建议和我们 §1.2 的口径一致——**收在搜索页那颗「连接」按钮上，只出现一次**，之后选
Wi-Fi、输密码、配网进度都没有系统框。手机已在该热点上时（上次留下的、或系统记住后自动重连）
直接跳过，零点击。
