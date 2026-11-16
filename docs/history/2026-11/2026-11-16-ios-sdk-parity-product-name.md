# iOS 涂鸦桥接对齐 Android、设备页文案改用涂鸦产品名

> 文档类型：Historical Change Record
> 日期：2026-11-16；环境：远程 SSH 服务器
> 分支与起始版本：main / 8cb3c28

## 依据与范围

1. iOS 配网搜不到 Wi-Fi 列表。同一个场景涂鸦 iOS 和 Android 调的是不同方法，要按 iOS 文档补齐 / 改正，交互和表现与 Android 一致（Android 已测过一轮）。
2. 花盆、割草机相关页面里称呼设备的「东方金穗」，改成这台设备在涂鸦平台设的产品名，取法和字段同 Android。外部通用页面（登录、我的、关于、隐私政策 / 用户协议、应用名）不变。

## 原因：iOS 为什么没有 Wi-Fi 列表

11-16 上午补的 iOS 蓝牙桥接里，扫描结果 `supportWifiList` 写死成 false，`queryDeviceConfigState` 直接回 `ble_wifi_list_unsupported`，所以 Dart 从不问设备要列表，下一页只能手动输入 Wi-Fi 名。Android 走的是 `IMultiModeActivator.queryDeviceConfigState`，iOS 对应的是另一套方法，当时没接。

## iOS 与 Android 方法对照（本次补 / 改的）

| 桥接方法 | Android | iOS（本次） |
| --- | --- | --- |
| `queryDeviceConfigState`（设备自报 Wi-Fi 列表） | `IMultiModeActivator.queryDeviceConfigState(MultiModeQueryBuilder)` | `ThingSmartBLEWifiActivator.connectAndQueryWifiListWithUUID:success:failure:`，列表从 `bleWifiActivator:didScanWifiList:uuid:error:` 回来；SDK 无超时参数，按 Dart 的 timeoutMs（30 秒）兜底 |
| 扫描结果 `supportWifiList` | `ScanDeviceBean.flag` 的 `SCAN_WIFI` 位 | `ThingBLEAdvModel` 没有对应能力位，一律 true；查不到时 Dart 不拦路，回落手动输入 |
| `pairBleDevice`（查过列表后） | 并行配网器，复用扫到的 bean | `pairDeviceWithUUID:token:ssid:pwd:timeout:` 复用查列表时的蓝牙连接；没查过列表仍走 `startConfigBLEWifiDeviceWithUUID:…` |
| `deviceProductName` | `getActivatorDeviceInfo(productId, uuid, mac)` → name | 同样取设备的 productId + uuid，`ThingSmartBLEManager.queryDeviceInfoWithUUID:productId:` → name |
| `deviceLinkState` | `isBleLocalOnline` + DeviceBean 各通道 | `deviceStatueWithUUID`（蓝牙）+ 设备模型 `isCloudOnline` / `isLocalOnline`（按属性名安全读，读不到按 `isOnline` 且蓝牙没连 = Wi-Fi 在线） |
| `bleConnectDevice` | `connectBleDevice` + 连接状态回调 | `connectBLEWithUUID:productKey:success:failure:`，已连着直接回，默认 15 秒超时 |
| `publishDpsWithMode` | `publishDps(String, ThingDevicePublishModeEnum)` | `publishDps:mode:success:failure:`，Internet / Local / Auto 同名映射 |
| `deviceMessages`（消息通知页） | `getMessageListByMsgSrcId` | `ThingSmartMessage.fetchEncryptMessageDetailListWithListRequestModel:`（`ThingSmartMessageDetailListRequestModel` 带 msgType / msgSrcId / limit / offset），每条消息属性原样带回 |
| 设备告警 `pushMessage` / `warn56` | `registerWarnMessageListener` | `ThingSmartDeviceDelegate` 的 `device:warningInfoUpdate:`，事件形状同 Android |

另修：`startConfigBLEWifiDeviceWithUUID` 的 failure 是 `ThingFailureHandler`（不带参数，涂鸦 Swift 示例为 `failure: { }`），上午那版写成带 `error` 参数，编译会报错，已改。

未接（Dart 已按「本端未接入」返回、不影响页面）：`bleReadRssi`、`requestWifiSignal`、`deviceOperateLogs`（当前无页面调用）；`messagesByTime`、`startPushListen`（只在调试台 / 诊断日志里用，iOS SDK 没有按时间窗取消息和 MQTT 推送监听的公开接口）。

## 设备页文案：涂鸦产品名

- `FlowerpotState.productNameFor` 照旧每次进页现问涂鸦，问到的名字记在本次会话（`productNameOf`），页面第一帧就有名字；设备列表刷新后每台现问一遍；退出登录清空。
- 页面称呼设备统一走 `productNameLabel(deviceId)`：涂鸦产品名，还没问到 / 问不到时说「设备」，不再出现「东方金穗」。
- 改到的页面：首页（帮助话题、设备图读屏标签）、行为、显示、听觉、LED、触摸、振动、植物检测设置页（`DeviceProductNameRefresh` 进页现问）。
- 不改：登录、我的、关于、隐私政策 / 用户协议、应用名（外部通用页面，仍为「东方金穗」）；割草机页面原本没有「东方金穗」。

## 待在 Mac 上核对的 SDK 接口

服务器无 Xcode、无 `ios/TuyaSDK`，以下按涂鸦 iOS 文档写，编译报错时以 Pods 头文件为准修正：

- `connectAndQueryWifiList(withUUID:success:failure:)`（文档 Swift 示例写作 `connectAndQueryWifiList(UUID:)`）、`pairDevice(withUUID:token:ssid:pwd:timeout:)`、代理 `bleWifiActivator:didScanWifiList:uuid:error:`，Wi-Fi 列表元素格式文档未写（字典 / 字符串 / 模型三种都认，原样放 raw）；
- `ThingSmartBLEManager`：`deviceStatue(withUUID:)`、`connectBLE(withUUID:productKey:success:failure:)`（failure 不带参数）、`disconnectBLE(withUUID:success:failure:)`；
- `ThingDevicePublishMode` 的 `.internet` / `.local` / `.auto`；
- 模块 `ThingSmartMessageKit`，`ThingMessageType` 的 `.alarm` / `.family` / `.notice`，`ThingSmartMessageDetailListRequestModel` 字段类型；
- `ThingSmartDeviceDelegate` 的 `device:warningInfoUpdate:`（没有时只是不回调）。

## 验证

未编译、未运行测试、未真机（服务器无 Flutter / Xcode）。待本地：`flutter analyze` 与设置页 / 首页用例；`pod install` 后 Xcode 编译；iPhone 进搜索页点设备后能列出设备扫到的 Wi-Fi，选网络输密码配网成功；设备设置页文案显示涂鸦产品名；割草机 Wi-Fi 断开时降级蓝牙下发；消息通知页有消息。

## 回滚

撤销本次提交即恢复为 iOS 手动输入 Wi-Fi 名、设备页文案「东方金穗」。
