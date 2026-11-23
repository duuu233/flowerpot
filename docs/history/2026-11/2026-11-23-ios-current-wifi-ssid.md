# iOS 配网页自动带出手机当前 Wi-Fi 名称

> 文档类型：Historical Change Record
> 日期：2026-11-23；环境：远程 SSH 服务器
> 分支与起始版本：main / c0d26f3

## 依据与范围

反馈：iOS 设备搜索后进配网页，Wi-Fi 名称不会自动出来，要手动输入；有时要自己从列表里选，有时什么都没有只能手填。期望像 Android 一样自动带出手机当前连接的 Wi-Fi。要求先确认涂鸦 SDK 能否获取，不行再去开发者账号开 App 的 Wi-Fi 信息权限。

## 原因

- Dart 侧逻辑两端相同：配网页把 `scanWifi` 返回的当前网络名（`WifiScan.current`）自动填入，搜索页走蓝牙时也带一份 `routerSsid`。iOS 上这个值一直是空，所以总要手填。
- iOS `scanWifi` 用 `NEHotspotNetwork.fetchCurrent` 读当前 SSID，系统要求两个前提，工程里都没有：
  1. **Access WiFi Information** 能力：仓库里没有 `.entitlements` 文件，Runner 也没有 `CODE_SIGN_ENTITLEMENTS`（2026-08-20 记录和发布就绪检查里已指出，一直未补）；
  2. **定位权限（精确位置）**：iOS 端从未引入 CoreLocation、从未申请定位（Info.plist 只有用途说明）。
  缺任一项，系统接口只返回空、不报错。
- 「有时要自己选」：设备固件支持回报 Wi-Fi 列表（`supportWifiList`）且这次查询成功时，配网页「切换」里有设备扫到的列表可选；查询失败或不支持就只剩手动输入。两种情况 Wi-Fi 名称框本身都是空的，原因同上。
- 涂鸦 SDK：`ThingSmartActivator.currentWifiSSID` 内部同样调用系统接口，受同样的能力与定位限制（涂鸦文档口径，本机无 iOS SDK 源码与 Xcode，未实测），不能绕过，所以仍用系统接口。

## 改动

- 新增 `ios/Runner/Runner.entitlements`：`com.apple.developer.networking.wifi-info = true`；Runner 的 Debug / Release / Profile 三个配置加 `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements`。
- `Info.plist`：新增 `NSLocationTemporaryUsageDescriptionDictionary`（键 `WiFiSSID`，用于临时申请精确位置）；`NSLocationWhenInUseUsageDescription` 文案写明用于读取当前 Wi-Fi 名称。
- `AppDelegate.swift` 新增 `WifiSsidReader`：没问过定位先弹授权框并等用户答完（最多 60 秒）；有权限但精确位置关着时临时申请精确位置；然后 iOS 14 起 `NEHotspotNetwork.fetchCurrent`、iOS 13 `CNCopyCurrentNetworkInfo` 读 SSID。`scanWifi` 改走它。用户拒绝定位时照旧返回空，页面仍可手动输入。
- Dart 未改。

## 需要在开发者账号与 Xcode 完成

- Apple Developer → Identifiers → App ID `com.common.yikaltdtext` 勾选 **Access WiFi Information**，保存后重新生成（或让 Xcode 自动签名刷新）描述文件。未勾选时，带了这个 entitlement 的包会签名失败（描述文件不包含该能力）。
- Xcode 打开工程，Runner → Signing & Capabilities 应能看到 Access WiFi Information；Archive 后在导出包里核对 entitlement。

## 补充（同日）：加上 Hotspot Configuration

- 用户要求把 AP 热点配网所需的 Hotspot Configuration 一并加上。iOS 连设备热点用的是 `NEHotspotConfigurationManager.apply`，需要 `com.apple.developer.networking.HotspotConfiguration`，此前同样缺失。
- `Runner.entitlements` 新增 `com.apple.developer.networking.HotspotConfiguration = true`。代码未改。
- 开发者账号的 App ID 需同时勾选 **Hotspot** 与 **Access WiFi Information** 两项能力，再刷新描述文件。

## 验证

服务器上没有 Xcode / Flutter，未编译、未签名、未真机（两项能力均如此）。需要在 Mac 上 Archive，iPhone 首次进搜索页同意定位（精确位置），确认配网页 Wi-Fi 名称自动填为手机当前网络；拒绝定位时可手动输入。

## 回滚

删除 `Runner.entitlements` 与三处 `CODE_SIGN_ENTITLEMENTS`，`scanWifi` 改回直接 `NEHotspotNetwork.fetchCurrent`。
