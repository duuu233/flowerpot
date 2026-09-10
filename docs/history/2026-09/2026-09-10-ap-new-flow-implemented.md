# 配网改用涂鸦「热点配网新流程」：SDK 自己连热点，系统授权框消失

> 文档类型：Historical Change Record
> 日期：2026-09-10
> 环境：SSH（无 Flutter/Dart SDK、无 Android SDK）
> 分支与起始版本：main / f105bd0
> 范围：`android/.../MainActivity.kt`、`lib/src/tuya/{tuya_models,tuya_repository}.dart`、`lib/src/state.dart`、搜索页与连接 Wi-Fi 页、对应用例
> 权威来源：`docs/reference/tuya-ap-mode-android.md`（官方文档存档）

## 背景

产品要求：配网过程不要系统授权框。前一份记录已查明官方「热点配网新流程」里
**SDK 自己会连 AP 热点**，接口在 7.5.1 里就有。本轮按产品口径（**设备固件 TuyaOS ≥ 3.6.1**）
把整条动线切过去。

## 变更内容

### Android 桥接（`MainActivity.kt`）

新增三个方法，全部沿用现有的反射风格（SDK 没链接时工程仍要能编过，见文件头注释）：

| 方法 | 做什么 |
| --- | --- |
| `apQueryDeviceWifi` | `ThingApActivatorBuilder().setContext()` → `newOptimizedActivator()` → `ApQueryBuilder` → `queryDeviceConfigState()`。**这一步里 SDK 自己连上设备热点**，并回读「设备扫到的 Wi-Fi 列表」（ssid / rssi / sec） |
| `apStartPairing` | 复用同一个配网器，`ApActivatorBuilder.Builder()` 填 ssid / pwd / **毫秒** timeout / token / securityConfig + listener → `startActivator()` |
| `apStopPairing` | `stopActivator()` + `onDestroy()`，放掉配网器与它持有的热点连接 |

`optimizedActivator` 跨方法保留——查列表和开始配网必须是同一个实例，换了实例热点连接就没了。
`apStopPairing` 放在 `ensureReady` 之前处理：SDK 没起来时也可能有残留配网器要放。

### Dart

- `DeviceWifiNetwork{ssid, rssi, sec}`：**设备视角**的 Wi-Fi。`needsPassword`（sec≠0）与
  `minimumPasswordLength`（2≦sec≦5 时 8 位）直接来自文档口径，可以提前挡掉短密码。
- `TuyaRepository`：`apQueryDeviceWifi` / `apStartPairing` / `apStopPairing`（Mock 同步补齐）。
- `FlowerpotState`：`connectDeviceForPairing()`、`pairViaDeviceHotspot()`、`stopDevicePairing()`、
  `deviceWifiNetworks`。三步进度（`PairingStage`）照旧驱动进度页。

### 页面

- **搜索页**：扫到设备 → 停 600ms → `connectDeviceForPairing()`（**SDK 连热点**）→ 成功才进
  「连接 Wi-Fi」。连不上（老固件 / 设备已离开配网态 / 超时）就退回列表并把原因说出来。
- **连接 Wi-Fi 页**：`_pair()` 直接调 `pairViaDeviceHotspot()`——不再取令牌、不再连热点、
  不再有 `hotspot_manual_required` 那条引导路径（连同那张卡与「已连接热点，开始配网」按钮
  一起删除）。「切换 Wi-Fi」列的是**设备扫到的**网络，不再是手机扫到的。

## 关键决策

- **原流程整套保留但不再被 UI 调用**（`pairViaHotspot` / `prepareForPairing` /
  `joinDeviceHotspot` 都还在）。新流程只对新固件有效，真机验不过时改回去只是换一个调用点。
- **超时单位**：新流程 `setTimeout` 是**毫秒**，原流程 `setTimeOut` 是**秒**。已在代码注释里
  标出——这两个名字只差一个大小写，混了就是 1000 倍。
- **手机侧扫热点仍然保留**：搜索页还是靠它「发现有设备在」并展示给用户。真正的连接交给 SDK。

## 验证结果

- **本机无 Flutter/Dart SDK、无 Android SDK**：`flutter analyze`、`flutter test`、Kotlin 编译
  **均未执行**。改动过的 6 个 Dart 文件与 3 个测试文件过了自写的括号配平检查。
- 用例改动（**未运行**）：`state_pairing_test.dart` 新增「连设备 → 读设备扫到的 Wi-Fi →
  下发凭据」一条；`pairing_page_test.dart` 删掉已下线的手动热点用例与
  `_ManualHotspotRepository`，令牌断言改为「Dart 侧不再单独取令牌」。
- **真机全部未验。**

## 未完成项与风险

- ⚠️ **反射调用的方法名/参数类型没有编译期保护**。`newOptimizedActivator`、
  `queryDeviceConfigState`、`setPwd`、`setTimeout` 这些名字来自官方文档 + AAR 常量池核对，
  但**没有在真机上跑通过**。一旦签名对不上，会以 `NoSuchMethodException` 失败。
- ⚠️ **固件版本是硬前提**：TuyaOS < 3.6.1 时新流程无效（预期 `207206` 或超时）。产品已确认按
  ≥ 3.6.1 处理，但**尚未拿到设备侧的确认**。
- ⚠️ 文档没写 SDK 在 Android 10+ 用什么机制连热点，**是否仍弹一次系统框必须真机验证**。
- iOS 侧未动：`activator_wifiAp_ios` 的流程图仍是「引导用户连接到设备热点」，等价能力待查。
- `getDeviceSecurityConfigs` 暂未接入（文档标注为可选参数），`securityConfig` 目前传空。
