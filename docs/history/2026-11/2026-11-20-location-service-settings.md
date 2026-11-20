# 搜索设备「请打开系统定位服务」：按钮改去系统定位开关页

> 文档类型：Historical Change Record
> 日期：2026-11-20；环境：远程 SSH 服务器
> 分支与起始版本：main / 9f4399c

## 依据与范围

反馈：小米安卓手机上搜索设备一直提示「请打开系统定位服务」，而定位权限已经允许。小米的系统定位总开关要在下拉控制中心或系统设置里单独打开，应用权限页里打开权限没用。

## 原因

- 提示本身没错：`bleProbe` 用 `LocationManager.isLocationEnabled`（Android 9+）检测的是系统定位总开关，不是应用权限；总开关关着时 BLE 扫描不报错、结果为空。
- 问题在出路：提示下的「去系统设置」固定打开应用详情页（`ACTION_APPLICATION_DETAILS_SETTINGS`），那里只有应用权限，用户看到「定位已允许」后无从下手。
- 两条提示文案里写了 `**` 加粗，页面是普通 `Text`，星号原样显示。

## 改动

- 原生桥接新增 `openLocationSettings`：Android 打开 `Settings.ACTION_LOCATION_SOURCE_SETTINGS`，打不开时退回应用设置页；iOS 无可直达的系统定位开关页、BLE 扫描也不依赖它，同名方法落到应用设置页。
- `TuyaRepository.openLocationSettings` / `FlowerpotState.openLocationSettings`（失败退回 `openAppSettings`）。
- 搜索页「去系统设置」：蓝牙可用、两项权限都已给、只差定位总开关时去定位开关页；其余情况（缺权限等）仍去应用设置页。按钮文字未改。
- 两条蓝牙提示去掉 `**`。
- `MockTuyaRepository` 增加 `locationSettingsOpens`；`device_search_page_test.dart` 新增用例：只差定位总开关时点按钮去定位开关页、文案不含 `**`，缺定位权限时仍去应用设置页。

## 验证

服务器上没有 Flutter / Android SDK，未编译、未运行测试、未真机。需要本地运行 `flutter test test/features/devices/device_search_page_test.dart`，并在小米真机上关掉定位总开关进入搜索页，点「去系统设置」应进入系统定位开关页。

## 回滚

按钮的 `onPressed` 改回 `state.openAppSettings()` 即可；新增桥接方法不调用时无影响。
