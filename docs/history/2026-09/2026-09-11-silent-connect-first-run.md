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
