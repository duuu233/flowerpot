# iOS 设置页顶部设备名多出数字、时有时无、最后为空

> 文档类型：Historical Change Record
> 日期：2026-11-26；环境：远程 SSH 服务器
> 分支与起始版本：main / 5472aa3

## 依据与范围

用户反馈（花盆，iOS）：设备列表 → 设备详情 → 帮助中心 → 返回 → 设置，设置页顶部设备名称末尾多了数字「4」；反复返回再进，「4」时有时无，最后设备名称整个不显示。Android 无此问题。

## 原因

- 设备名称的显示规则（2026-11-19 起 `FlowerpotState.deviceDisplayName`：本机改过名 → 自定义名；否则按产品 ID 现查的涂鸦产品名；都没有才用涂鸦设备名；最后兜底「设备」）用在设备列表、花盆首页顶栏、设备信息页、割草机页面，**唯独花盆设置页顶部卡片**（`DeviceSettingsPageModel.fromDevice`）直接取涂鸦原始设备名 `device.name`。
- 涂鸦原始设备名是激活时由云端生成的，同一产品在家庭里多次激活会自动加序号（例如「花盆test4」）；列表与首页显示的是产品名「花盆test」，设置页就比它们多出数字。
- 原始设备名只随整台设备信息推送变化（iOS `deviceInfoUpdate` / Android `onDevInfoUpdate`，Dart 侧整体覆盖快照）。iOS 上来回进出页面期间名字时有时无、最后为空，说明推送里的原始名在变或为空；具体是哪次推送带来的变化，需要真机联调日志确认（本次新增日志，见下）。不管原始名怎么变，设置页改走显示规则后都不再受影响。

## 改动

- `DeviceSettingsPageModel.fromDevice` 新增可选参数 `displayName`；`DeviceSettingsPage` 传入 `state.deviceDisplayName(device)`，顶部卡片与列表、首页同一规则。不传时仍退回涂鸦设备名（测试 / 预览）。
- 「其他设置」里的重新配网（离线提示、确认）与移除设备确认对话框，称呼设备也改用 `deviceDisplayName`（原来同样用涂鸦原始名，会出现「花盆test4」）。
- `FlowerpotState._applyDeviceUpdate`：推送里的涂鸦原始设备名与当前不同时写一条联调日志「设备名 ← <id> 推送里的涂鸦设备名「旧」→「新」」（受联调日志开关控制，用户包不记）。设备信息页联调弹窗里的「名称」仍显示原始名，便于核对。
- 测试：`device_settings_page_test.dart` 新增 `fromDevice` 传显示名 / 不传时退回原始名。

## 验证

- 服务器没有 Flutter / Dart 工具链，未运行 `dart analyze`、`flutter test`，未编译、未真机。
- 需在 iOS 真机按原路径（列表 → 详情 → 帮助中心 → 返回 → 设置，反复进出）确认设置页名称与列表一致、不再多数字、不为空；同时在联调日志框看是否出现「设备名 ←」记录，以确认 iOS 推送里原始名的变化。

## 回滚

还原上述四个文件的改动即可；不涉及存储、协议与原生桥接。
