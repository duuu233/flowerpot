# iOS 配网列表与设备列表按产品 ID 取涂鸦名称和图片

> 文档类型：Historical Change Record
> 日期：2026-11-17；环境：远程 SSH 服务器
> 分支与起始版本：main / 1bec5c4

## 依据与范围

产品反馈 iOS 与 Android 表现不一致（Android 正常）：

1. 配网时搜索页「连接」那一行的设备名称，固定按产品 ID 读取涂鸦产品名；图片同样按产品认。
2. 设备列表默认显示按产品 ID 读到的涂鸦名称，用户自定义过设备名则显示自定义名称。
3. 「连接 Wi-Fi」页顶部图片一并核对。

## 核对结果

- 「连接 Wi-Fi」页与配网进度页顶部是同一张 `pairing_wifi_setup_illustration.gif`（48 帧、每帧 60ms、无限循环、透明底），Dart 两端同一份代码，没有 iOS 分支；本次未改。
- 设备列表的图取涂鸦产品图 `iconUrl`：Android `deviceMap` 带 `DeviceBean.getIconUrl`，**iOS `deviceMap` 没带这个字段**，iOS 设备列表那一列一直是空图。
- 设备列表名称：两端都取涂鸦设备名（`DeviceBean.name` / `ThingSmartDeviceModel.name`）。涂鸦设备名默认就是产品名，用户改名后是自定义名，与需求口径一致。
- 搜索页那一行：图标按广播 pid 认花盆 / 割草机，名称取 `queryDeviceProductInfo`（Android `getActivatorDeviceInfo`，iOS `ThingSmartBLEManager.queryDeviceInfoWithUUID:productId:`）。iOS 只按 `productId` 一个属性读广播 pid，读不到时 Dart 不查名字，行上退回广播名 / mac 尾号，图标退回蓝牙图标；iOS 解析产品信息时 NSNull 会被当成 "<null>"。

## 改动

- iOS `deviceMap` 补 `iconUrl`（`ThingSmartDeviceModel.iconUrl`）。
- iOS 广播 pid 依次读 `productId` / `productKey` / `pid`；`queryDeviceProductInfo` 没带 pid 时用本轮扫到的那条广播里的。
- iOS `productInfoMap`：name / icon / productId 按多种键名读，外层包 result / data 也认，NSNull 与空串算没有；查询成功 / 失败都写一条 `pairingLog`（uuid、pid、名字、原样返回），真机上可直接看到 SDK 回了什么。
- Dart `BleProductInfo` 增加 `productId`；搜索页图标：广播 pid 认不出时再按云端回的产品 ID 认，仍认不出且涂鸦有产品图时画产品图（加载失败回到蓝牙图标）。
- 设备列表：设备名为空时按产品 ID 问到的涂鸦产品名显示（`productNameLabel`），否则照旧显示涂鸦设备名（默认产品名 / 自定义名）。
- 新增用例：广播 pid 认不出、云端回花盆产品 ID 时画花盆图并显示涂鸦产品名。

## 待在 Mac 上核对

- `ThingSmartDeviceModel.iconUrl` 属性名（编译报错以 Pods 头文件为准）。
- `queryDeviceInfoWithUUID:productId:` 回的字典键名：看配网调试日志里 `ble product:` 那一行的 raw。
- 若 iOS 广播里三个属性都读不到 pid，需按扫描结果 raw 再补字段名。

## 验证

未编译、未运行测试、未真机（服务器无 Flutter / Xcode）。待本地 `flutter analyze`、`flutter test test/features/devices/device_search_page_test.dart`，`pod install` 后 Xcode 编译；iPhone 实测搜索页设备行名称与图、设备列表图与名称（含改名后）。

## 回滚

撤销本次提交即可，不涉及 DP、接口或持久化数据。
