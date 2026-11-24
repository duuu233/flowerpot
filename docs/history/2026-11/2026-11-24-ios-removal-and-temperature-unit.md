# iOS 设备被移除不消失、切温标后读数未换算

> 文档类型：Historical Change Record
> 日期：2026-11-24；环境：远程 SSH 服务器
> 分支与起始版本：main / 7102743

## 问题

1. 设备被移除（解绑）后，Android 列表自动去掉；iOS 只显示离线，下拉刷新才消失。
2. 温度在摄氏 / 华氏之间切换后，iOS 显示没有换算（Android 正常）。

## 原因与改动

**设备移除（iOS 原生）**

- `deviceRemoved:` 原来用 `device.deviceModel?.devId` 取 id。设备被移除时 SDK 已先清掉缓存，`deviceModel` 多半是 nil，`guard` 直接返回，`removed` 事件没发出去；先到的上下线回调只把它标成离线。
- 改为按实例反查 `watched` 里登记的 id（`watchedId(of:)`），取不到再退回 `deviceModel`。
- 另把 `currentHome` 挂上 `ThingSmartHomeDelegate`，实现 `home:didRemoveDeivce:`（SDK 方法名本身如此拼写），直接带 devId，作为第二条移除通知。
- 两条通知统一走 `deviceWasRemoved`：主线程上只在该设备仍在 `watched` 时停止监听并发 `removed`，重复的第二次不再发。Dart 侧事件形状不变。

**温标换算（Dart，两端通用）**

- DP112 按 DP146 当前温标上报，但切温标后设备先回 146，112 要等下一次上报才换成新单位。原逻辑只改标签、不碰读数，这段时间显示「°F 标签 + 摄氏数值」（反之亦然），刷新或等设备重报后才对。各端看到的差异取决于 112 重报的时机。
- `MethodChannelTuyaRepository._device` 在快照里记下当前读数是按哪个温标报的（`_airTemperatureFahrenheit`，非 DP）：第一次见到设备或 112 的值变了，按此刻的 146 认单位；只来 146 时沿用旧读数的单位，再用 `DeviceControlSettings.convertTemperature` 换到当前温标。设备按新单位重报 112 后原样显示，不二次换算。
- 设置页下发温标成功、设备回报前的本机乐观更新（`FlowerpotState` 设置覆盖）同时换算 `sensors.airTemperature`（`SensorSnapshot.withAirTemperature`）。
- 温度历史曲线（DP164）未改。

## 测试

- `test/tuya/device_updates_test.dart`：只来 146 时读数换算、其它 DP 不改变读数单位、华氏重报 112 不二次换算、切回摄氏；146 与 112 同一条报文按设备值显示。
- `test/tuya/device_control_settings_test.dart`：`convertTemperature` 互换与保留一位小数。

## 验证

服务器上没有 Flutter / Dart / Xcode，未编译 Swift、未运行 analyze 与测试、未真机。需要本地：`dart analyze lib test`、`flutter test test/tuya`；iOS 编译确认 `ThingSmartHomeDelegate` 的 `home(_:didRemoveDeivce:)` 签名无告警；真机在另一台手机或设备端解绑，确认 iOS 列表即时去掉；切换温标后首页温度卡、温度状态页数值立即换算。

## 回滚

还原本次提交即可。
