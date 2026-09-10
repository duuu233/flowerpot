# 2026-09-10（晚）把配网进度接到涂鸦真实的 `onStep` 上

## 背景（用户提供的对照）

测试用智能生活 App 在**同一台设备**上配网成功（先提示「4G 激活失败」，切到 Wi-Fi 配网
后成功），它展示的进度是：

```
设备连接建立成功
Wi-Fi配置已下发
设备连接路由器成功
设备激活中
设备即将上线
```

用户要求：行为和它一样就行，**页面展示的内容保持现在这些**；我们同样要 Wi-Fi 配网，
而它走的是 AP 模式。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `da5a054`。

## 这串文字说明了什么

那 5 句正是涂鸦 activator 的 **`onStep` 回调**在 UI 上的映射——官方 AP 新流程文档里
`ApActivatorBuilder.setListener` 的 `onStep(String step, Object data)` 那一项，文档只说
「和原有配网参数一致」，没有列出常量名。

两个直接结论：

1. **SDK 确实会逐步上报真实进度**，包括设备连上路由器、云端激活中。
2. 我们的第三步「连接云端」一直是**装的**——`_cloudStageDelay()` 给 1–2 秒随机停留后
   直接按成功处理，因为当时没有任何真实信号可用。现在有了。

另外这条反馈也旁证了上一步的决定：智能生活在 AP 模式下能配成、且不弹入网授权框，
而它的 AP 流程里本来就有「去连接」那一步把用户送去系统 Wi-Fi——正是
`da5a054` 实现的那条路。

## 改动

**页面文案一行没动**（产品要求），动的是进度从哪来。

### 原生 `MainActivity.kt`

`callbackProxy` 的 `when (method.name)` 里加 `"onStep"` 分支：原样把步骤名转成事件
（`{type: 'pairingStep', step: …}`）推给 Dart，**并打一行 `pairing step: …` 日志**。
日志是故意的：常量名官方没列，真机跑一次就能从 logcat 里确认，之后再改成按名字精确映射。

### `lib/src/tuya/tuya_repository.dart`

抽象加 `Stream<String> get pairingSteps`；实现从既有的 `_rawEvents` 里筛
`type == 'pairingStep'`（和 `deviceUpdates` / `otaUpdates` 共用同一条事件通道）。

### `lib/src/state.dart` — `pairViaDeviceHotspot`

- 配网期间订阅 `pairingSteps`，每收到一条就推进阶段：**第一条**意味着与设备的通道已经
  建立 ⇒ `sendingWifi`；**之后的**都属于「设备在连路由器、连云激活」⇒ `connectingCloud`。
  按**到达顺序**判断而不是按名字——顺序是 SDK 保证的，名字等真机日志确认后再精确映射。
- **涂鸦报过进度就不再用那 1–2 秒假停留**：`if (tuyaSteps.isEmpty)` 才走
  `_cloudStageDelay()`，它从此只是「一条上报都没有」时的兜底。
- 失败消息里带上**最后到过的那一步**：`｜连设备 8.2s · 配网 120s · 涂鸦进度「xxx」`。
  这比失败码更能说明卡在哪——比如有「Wi-Fi 配置已下发」却最终超时，就说明设备收到了
  凭据、是它连路由器那一段的问题（对应 207210/207211/207212/207213）。
- `finally` 里取消订阅。

### `test/support/mock_tuya_repository.dart`

加 `pairingSteps` 广播流与 `emitPairingStep()`，用例可以模拟 `onStep`。

## 验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链。静态自检：四个改动文件括号配平、与
HEAD 同基线。现有用例不受影响：mock 的 `pairingSteps` 默认不发任何东西 ⇒ 走
`tuyaSteps.isEmpty` 的兜底路径，行为与改动前一致。

## 遗留

- **真机跑一次，从 logcat 抓 `pairing step: …`**，把常量名记下来，然后把「按到达顺序」
  改成按名字精确映射，并考虑是否把那 5 句直接用作步骤文案（需产品确认，本次没动文案）。
- 「4G 激活失败 / 切 Wi-Fi 才成功」这条现象值得留意：设备连云激活要走外网，手机挂在
  设备热点上时没有外网，这正是我们把取令牌与取安全配置提前到搜索页的原因。若真机上
  出现同类失败，先看 207214/207215/207219（连云相关）。
