# 设备名称按手机系统语言动态显示

> 文档类型：Historical Change Record
> 日期：2026-11-19；环境：远程 SSH 服务器
> 分支与起始版本：main / 6fe3f27

## 依据与范围

真机（系统语言 zh-Hans-US，新包）联调日志：按产品 ID `ehbx83xdh9jkmxvz` 现查的涂鸦产品名已经是「花盆test」，但设备列表仍显示「Flower Pot Test」。涂鸦平台上该产品的多语言名称是：简体中文「花盆test」、英语「Flower Pot Test」；「产品名称」一栏的「YUSEN-智能花盆」App 取不到。产品确认显示「花盆test」是对的，要求设备名称按手机系统语言动态显示。

## 原因

列表原来显示涂鸦设备名（`device.name`）。这个名字是配网激活那一刻，按 App 当时的请求语言存成产品名的；这台设备当时按英文激活，所以存成了「Flower Pot Test」，之后不会随系统语言改变。涂鸦设备名只有这一个字段，激活时自动取的名字和用户改的名字无法区分；后端也没有设备名称的客户端接口（见 `2026-11-19-ios-localization-zh.md`）。

## 改动

- `FlowerpotState.deviceDisplayName` / `deviceDisplayNameOf`：页面统一用它取设备名，按以下顺序取：
  1. 本机在 App 里改过名，且涂鸦设备名仍等于改后的名字 → 显示自定义名；
  2. 否则显示按产品 ID 现查的涂鸦产品名（`productNameFor`，每次设备列表刷新、进设备页都会现查），名称随 App 本地化语言，iOS 和 Android 都跟随系统语言；
  3. 产品名还没查到或查不到 → 涂鸦设备名；设备名为空 → 「设备」。
- 本机改名记录：`renameDevice` 成功后，按涂鸦 uid 在 SharedPreferences 里记录 `customDeviceNames:<uid>`（设备 ID → 名字）；会话开始时读回，解绑设备时删掉对应项，退出登录时清空内存。换手机、重装 App，或在其它 App 里改的名字，本机都认不出来，会显示产品名。
- 使用显示名的页面：设备列表、花盆设备首页顶栏、设备信息页名称卡片和改名弹窗初始值、割草机控制页标题、割草机删除确认文案。设备信息页的诊断行仍是涂鸦原始设备名。
- 联调日志「设备列表快照」：名称来源改为按上面的规则说明；新增「涂鸦设备名（激活时存下）」「本机改名记录」两行；去掉原来的「设备名与产品名不一致」提示。
- 测试：新增 `test/state_device_display_name_test.dart`；设备列表用例新增「按产品名显示」，测试仓库默认查不到产品名，原有用例仍按设备名；设备信息页用例改为期望卡片显示产品名；快照用例同步。

## 已知表现

- 列表第一帧可能先显示涂鸦设备名，产品名查到后再换成产品名（产品名按要求不缓存）。
- Android 在 App 运行中切换系统语言后，要下拉刷新或重新进页面，才会按新语言重新查。iOS 切换系统语言会重启 App。

## 验证

服务器上没有 Flutter / Xcode，未编译，未运行测试，也未在真机上验证。只人工复核了 diff，核对了括号配平和 `git diff --check`。需要在本地运行 `flutter analyze` 和 `flutter test test/state_device_display_name_test.dart test/features/devices/device_list_page_test.dart test/features/devices/device_info_page_test.dart test/app/interaction_log_test.dart`。真机上：中文系统显示「花盆test」，英文系统显示「Flower Pot Test」；在 App 里改名后，列表显示改后的名字。

## 回滚

撤销本次提交即可。本机改名记录只是多存了一个 SharedPreferences 键，回滚后不再读取，不影响其它功能。
