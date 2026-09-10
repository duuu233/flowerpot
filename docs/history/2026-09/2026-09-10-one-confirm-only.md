# 2026-09-10（晚）确认框只弹一次：已持有连接的判断改为原生记账

## 产品疑问

> 为什么手机热点连设备还是有「要与智能花盆搭配使用的设备 / 取消 / 连接」这个弹出框？
> 搜索到的设备自动连接不行吗？

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `736f2d1`。

## 回答

**自动连接已经做到了**：App 自己挑中搜到的那台、自己发起连接，用户不需要选任何东西。
但「自动发起」和「零确认」是两件事——那个框是**系统在问用户是否允许本应用加入这个
网络**，Android 10+ 对所有第三方应用（包括涂鸦 SDK，它只是跑在我们进程里的库）都必弹，
没有任何公开 API 能抑制它或代替用户点。

**唯一真能没有框的情形**：该热点已经在手机的「已保存的网络」里。那时设备一开机手机就
自动连上了，整个过程不经过任何 App API，自然没有框；我们的代码检测到「已经连上」会直接
跳过。⚠️ 但我们自己用 `WifiNetworkSpecifier` 连上的那一次**不会**被系统保存（进程专属的
一次性连接），所以靠 App 连永远不会变成「记住了」——要变成记住，得用户在系统设置里手动
连一次。

「智能生活不弹框」最可能就是这个原因，值得在测试机上查一眼
**设置 → WLAN → 已保存的网络**里有没有 `smartlife_…`。

## 顺带修掉一个会让框**多弹一次**的问题

`_joinHotspotForPairing` 判断「是不是已经连上目标热点」靠的是
`scanWifi(refresh: false)` 回来的 `current`，而原生那个值取自
`WifiManager.connectionInfo.ssid`——**没有定位权限时它返回 `<unknown ssid>`**
（Android 8.1 起的限制），我们把它过滤成 `null`，于是判断成「还没连」，又发一次
`requestNetwork`，用户就看到**第二个**确认框。

Android 13+ 的权限门禁里 `ACCESS_FINE_LOCATION` 只是 `requested`（`NEARBY_WIFI_DEVICES`
才是 `required`），所以「给了附近设备权限、拒了定位权限」是完全可能出现的组合。

**改法：原生自己记账。** 新增 `boundHotspotSsid`，在 `onAvailable` 里连上并绑定成功时
记下目标 SSID，在 `unbindProcessNetwork()` 里清掉。`joinDeviceHotspot` 开头先判断：

```kotlin
if (boundHotspotSsid == target && boundNetwork != null && hotspotCallback != null) {
    success(result, false)   // 原地返回，不发 requestNetwork ⇒ 不弹框
    return
}
```

这条判断**不依赖任何权限、也不依赖系统怎么报当前网络**，所以「搜索页已经连过 ⇒ 配网那一步
不再弹」是确定的，而不是碰运气。

## 验证

**未验证。** 本机没有 Kotlin 工具链。静态自检：括号配平与 HEAD 同基线；`boundHotspotSsid`
四处引用（声明、判断、记录、清理）齐全。

## 遗留

- 真机确认框只出现一次（搜索页那一次），配网步骤不再出现第二次。
- 在测试机上查「已保存的网络」里有没有 `smartlife_…`，以验证「智能生活不弹框」的成因；
  若成立，产品可以决定是否把「首次请到系统设置连一次、此后免确认」写进引导文案。
