# 2026-09-11 涂鸦官方回复确认「连接热点是 App 的活」；日志直接上屏

## 一、涂鸦 SDK 官方回复（产品转达）

> 安卓端 AP 模式配网实现步骤如下（基于涂鸦 SDK）：
> 1. 设备准备：确保设备进入 AP 模式（Wi-Fi 指示灯慢闪），热点名以 `SmartLife_` 开头；
> 2. **连接热点：App 调用系统 API 自动连接设备热点**（Android 允许直接跳转 Wi-Fi 列表）；
> 3. 获取配网 Token & 安全配置：`getDeviceSecurityConfigs(...)`；
> 4. 查询设备扫描的 Wi-Fi 列表：`ApQueryBuilder` + `queryDeviceConfigState(...)`；
> 5. 提交配网信息：传入 SSID、密码、Token 和安全配置；
> 6. 监听结果：`IThingResultCallback` 处理成功/失败回调。

**第 2 步一锤定音**：连热点是 **App** 的活。这与我们此前的实测完全吻合，也解释了所有失败。

### 四条独立证据现在指向同一件事

| # | 证据 |
| --- | --- |
| 1 | 涂鸦官方回复：「App 调用系统 API 自动连接设备热点」 |
| 2 | 官方 AP 文档定义：「……**但用户需要手动切换手机的 Wi-Fi 设置**」 |
| 3 | git：`223bdae^`（有这一步）能配成；`223bdae` 改成"指望 SDK 自己连"后**全是 `207220`** |
| 4 | 四次真机实测：失败时手机**始终在路由器上**，SDK 从没把它切过去 |

⇒ 「SDK 会自己连热点」这条假设**彻底作废**。之前我据一次被污染的实验把这一步删掉，是错的。

## 二、改动

### 1. 把第 2 步接回「连接」按钮（`device_search_page.dart`）

`_connectAndOpen` 现在按涂鸦的顺序走：

```
① await _prepared           取 Token + 安全配置（**提前到还连着路由器时**，见下）
② connectDeviceHotspot()    App 连设备热点 ← 涂鸦步骤 2，系统框只在这一刻出现一次
③ connectDeviceForPairing() queryDeviceConfigState，让设备扫 Wi-Fi ← 涂鸦步骤 4
④ 跳「连接 Wi-Fi」页        用户从设备扫到的列表里选 + 输密码 ← 涂鸦步骤 5
```

②失败（用户点了系统框的「取消」）就把原因画在页面上，再点一次即可。

**与涂鸦步骤表的一处有意偏差**：涂鸦把「取 Token 与安全配置」排在第 3 步（连热点之后），
**那样走不通**——连上热点手机就没外网，取不到云端的东西。我们提前到搜索页进页面时预取。

### 2. 原生日志**直接打到页面上**（产品：「不看 logcat，我截图给你」）

- 原生新增 `trace(line)`：`Log.i` 照打，**同时**通过 EventChannel 推给 Dart
  （`{type: 'pairingLog', line: …}`）。`apQueryDeviceWifi` 的六行与 `pairing step:` 都改用它。
- `TuyaRepository.pairingLogs` 新增流；`FlowerpotState.pairingLog` 收集（每次连接/配网前清空，
  只留最近 20 行）。
- 搜索页失败时画出 `_PairingLogBox`：等宽字体、左对齐、**长按复制**。产品直接截图即可。

日志内容示例：

```
ap query: begin
ap query: activator=XxxOptimizedActivator
ap query: builder ok, timeout=35000ms
ap query: wifi before = SmartLife-A1B2
ap query: handed to SDK, waiting for callback
ap query: success in 1832ms, networks=8, wifi now = SmartLife-A1B2
```

这几行能分辨三种完全不同的故障：**配网器没建起来** / **反射签名对不上** /
**调出去了但回调永远不来**。

### 3. 失败文案「事实在前、猜测在后」

第一行就是 `【错误码】涂鸦原文｜用时 Xms · 手机在「Y」(是否设备热点)`；建议缩成一行放最后。
起因是产品反馈「感觉不是这个问题」——第一版把两条猜测排在最前面，真正的诊断被挤没了。

## 三、验证

**未验证。** 本机没有 Flutter/Dart/Kotlin 工具链。按 §6 清单自检：五个改动文件括号配平，
`state.dart` / `MainActivity.kt` 与 HEAD 同基线；`pairingLogs` 在抽象、实现、mock 三处都有；
`Clipboard` 已 import `services.dart`；`showAppMessage` 经 `design_system.dart` →
`widgets/widgets.dart` → `feedback/app_snackbar.dart` 导出，可用。

## 四、这一版复测要看什么

1. **系统框应当只在点「连接」时出现一次**，之后（选 Wi-Fi、输密码、配网）都不该有。
2. 若仍失败，页面上会有日志盒子——**长按复制或直接截图**即可，不用开 logcat。
   重点看 `wifi before` / `wifi now`：如果这时已经是 `SmartLife-…`，说明第 2 步成功了，
   问题在后面；如果还是路由器名，说明连热点这一步本身没成。
