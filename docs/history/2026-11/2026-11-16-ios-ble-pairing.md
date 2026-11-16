# iOS 补蓝牙发现与双模配网桥接

> 文档类型：Historical Change Record
> 日期：2026-11-16；环境：远程 SSH 服务器
> 分支与起始版本：main / 8123f6a

## 依据与范围

iPhone 安装蒲公英包后进搜索页提示「这台手机用不了蓝牙配网（探测蓝牙失败：原生涂鸦SDK尚未接入）」，热点方式已屏蔽，iOS 没有可用的配网路径。只改 iOS，Android 不动。

## 原因

包名一致（`com.common.yikaltdtext`），涂鸦 SDK 已在包里。iOS 原生桥接 `FlowerpotTuyaBridge` 只接了登录、设备、热点配网、OTA 等方法，蓝牙一个都没有。Dart 调 `bleProbe` 落到 `FlutterMethodNotImplemented`，`MethodChannelTuyaRepository._invoke` 把 MissingPluginException 统一翻成「原生涂鸦 SDK 尚未接入」。

## 改动（`ios/Runner/AppDelegate.swift`）

| 方法 | iOS 实现 |
| --- | --- |
| `ensureBlePermissions` | 建 `CBCentralManager` 触发系统蓝牙授权框，等状态定下来（最多 60 秒）；未授权回 `permission_denied` |
| `bleProbe` | `available` = 能取到 `ThingSmartBLEManager`；`supported` / `enabled` / `scanPermission` 取自 CBCentralManager 状态与 `CBCentralManager.authorization`；iOS 扫蓝牙不需要定位，`locationOn` / `locationPermission` 恒为 true |
| `startBleScan` | `ThingSmartBLEManager.startListening(true)`，按 `timeoutMs` 到时停扫并推 `bleScanStopped`；每台设备推 `bleDevice`（uuid / productId / mac / name / rssi / bound / raw） |
| `stopBleScan` | `stopListening(false)`：不清 SDK 发现缓存，停扫后紧接着配网要用 |
| `disconnectBleDevice` | 没在配网时 `ThingSmartBLEWifiActivator.stopDiscover()`；配网进行中不动 |
| `queryDeviceProductInfo` | `ThingSmartBLEManager.queryDeviceInfo(withUUID:productId:)` → name / icon |
| `pairBleDevice` | `ThingSmartBLEWifiActivator.startConfigBLEWifiDevice(withUUID:homeId:productId:ssid:password:timeout:120)`；结果走 `bleWifiDelegate` 的 `didReceiveBLEWifiConfigDevice` / `notConfigStateWithError`；130 秒兜底超时 `pair_timeout` |
| `queryDeviceConfigState` | 未接，回 `ble_wifi_list_unsupported`；扫描结果 `supportWifiList` 恒为 false，Dart 不会调到 |
| `openAppSettings` | 打开本应用系统设置页 |

`cancelPairing` 与退出登录同时了结进行中的双模配网。蓝牙部分整段在 `#if canImport(ThingSmartBLEKit)` 内；模块不在时 `bleProbe` 报 `available: false`（reason 写明缺 ThingSmartBLEKit），其余方法回 `ble_unavailable`，不影响其它功能编译。Dart 与页面未改。

扫描结果字段按属性名安全读取（`responds(to:)` 后 KVC），这一版 SDK 属性名不同时读成空、不崩，原样 `description` 放在 `raw`（调试包设备行可见）。

## 待在 Mac 上核对的 SDK 接口

服务器上没有 Xcode 和 `ios/TuyaSDK`，以下按涂鸦 iOS SDK 文档写，编译报错时以 Pods 里实际头文件为准修正：

- 模块名 `ThingSmartBLEKit`（canImport 为假时蓝牙整段不编译，探测会报缺模块）；
- `ThingSmartBLEManager`：`startListening(_:)`、`stopListening(_:)`、`delegate`、`queryDeviceInfo(withUUID:productId:success:failure:)`；代理 `didDiscoveryDeviceWithDeviceInfo:`（`ThingBLEAdvModel`）；
- `ThingSmartBLEWifiActivator`：`startConfigBLEWifiDevice(withUUID:homeId:productId:ssid:password:timeout:success:failure:)`、`stopDiscover()`、`bleWifiDelegate`；代理 `bleWifiActivator:didReceiveBLEWifiConfigDevice:error:`、`bleWifiActivator:notConfigStateWithError:`。

## 验证

未编译、未真机。待本地：`pod install` 后 Xcode 编译；iPhone 进搜索页确认授权框、能扫到花盆、产品名显示、输入 Wi-Fi 密码后配网成功并出现在设备列表。

## 回滚

撤销本次提交即恢复为 iOS 无蓝牙方法。
