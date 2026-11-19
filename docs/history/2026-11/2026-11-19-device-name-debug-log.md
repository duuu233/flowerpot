# 设备列表名称「Flower Pot Test」排查与联调日志排版、设备快照

> 文档类型：Historical Change Record
> 日期：2026-11-19；环境：远程 SSH 服务器
> 分支与起始版本：main / d94c57c

## 依据与范围

产品反馈：设备列表的设备名称仍显示「Flower Pot Test」，涂鸦平台上产品 `ehbx83xdh9jkmxvz` 的名称是「YUSEN-智能花盆」。要求查清原因，并像 Android 一样在左下角放调试日志：页面展示的数据、关键信息都打进日志，日志排版清楚，便于查看、复制。

## 核对结果

- 源码、资源、文档里都没有「Flower Pot Test」这个字符串。
- 设备列表名称两端走的是同一份 Dart 代码：`device.name` 不为空就显示它，只有为空时才用按产品 ID 查到的涂鸦产品名（`productNameLabel`）。`device.name` 是涂鸦 SDK 返回的设备名（Android `DeviceBean.getName`，iOS `ThingSmartDeviceModel.name`），即涂鸦云端给这台设备记的名字，不是按产品 ID 现查的产品名。
- 所以「Flower Pot Test」是涂鸦云端这台设备的设备名。涂鸦设备名在配网激活时生成、之后固定，可能的来路（推测，未经真机证实）：
  1. 激活时用的是产品当时的名字或其英文名：配网时手机系统语言为英文，SDK 按系统语言请求，设备名会落成产品的英文名；平台后来改的产品名不会回写到已激活的设备。
  2. 曾被改过名（本 App 或涂鸦 App）。
- 涂鸦 SDK 不提供「设备名是默认的还是改过的」标记，App 无法可靠区分，本次不改显示规则。
- 左下角「联调日志」浮层两端共用（`InteractionLogOverlay`），只有构建时带 `APP_DEBUG_TOOLS=false` 才不挂。iOS 无日志包是先 `flutter build ios --config-only --dart-define=APP_DEBUG_TOOLS=false` 再 Archive；该参数写在 `ios/Flutter/Generated.xcconfig` 的 `DART_DEFINES` 里，之后直接在 Xcode 里 Archive / Run 仍沿用这个参数，日志浮层就一直不出现。

## 改动

- 状态层 `logDeviceListSnapshot`：设备列表每次读取完成、各设备的涂鸦产品名都问完后，在联调日志里打一份「设备列表快照」，读取失败时也打。内容包括：
  - 头部：平台、手机系统语言（全部首选语言）、App 界面语言、涂鸦 uid、家庭、读取失败原因；
  - 每台设备一段：页面显示名称及来源、涂鸦设备名、按产品 ID 查到的涂鸦产品名（查询用的产品 ID、原样返回，截断到 300 字）、产品 ID（花盆 / 割草机 / 未识别）、设备 ID、在线、图片地址、固件版本、DP169；设备名与产品名不一致时单独标「⚠」。
- 按产品 ID 查产品名的原始结果（成功、没查到、异常）按设备记下，供快照使用；退出登录时清空。
- 日志框排版：每条日志单独一块，包括时间标签、加粗标题和等宽缩进的明细，条与条之间加分隔线。多行日志第一行作标题；只有一行、但用「；」或「 · 」串了几段的，拆成一段一行。只改显示，状态层记录的原文不变。
- 日志框按钮单独一排（窄屏可换行）：「复制全部」（条与条之间空一行）、「设备快照」（随时再打一份当前快照，用已问到的产品名）、「OTA日志」、「清空」、「收起」；每条右侧有「复制」。复制后在标题右侧显示「已复制…」2 秒。没有用全局 toast，因为日志框挂在 Navigator 外面，找不到 Overlay，toast 不会显示。
- 日志区最大高度从屏高的 45% 提到 55%，最低 220。
- 新增 `test/app/interaction_log_test.dart`：日志拆行解析、设备快照内容（显示名、来源、产品名、不一致标记）、日志框单条 / 全部复制。

## iOS 出带日志的包

Archive 前重新生成一次配置，不带 `APP_DEBUG_TOOLS=false`：

```bash
flutter build ios --release --config-only --dart-define=API_BASE_URL=https://api.yikaltd.com
```

然后在 Xcode 里 Archive。也可以检查 `ios/Flutter/Generated.xcconfig` 的 `DART_DEFINES`：其中的值是 base64 编码，解出来不能有 `APP_DEBUG_TOOLS=false`。

## 待在真机上核对

登录后打开日志，看「设备列表快照」：

- 「按产品 ID 查涂鸦产品名」如果是「YUSEN-智能花盆」，说明产品名没问题，「Flower Pot Test」是这台设备在涂鸦云端记的设备名。在 App 里把设备改名为「YUSEN-智能花盆」即可；也可以解绑后用系统语言为中文的手机重新配网，再看新设备名。
- 如果查到的产品名本身就是「Flower Pot Test」，并且手机系统语言是英文，说明涂鸦按系统语言返回了产品的英文名，需要在涂鸦平台的产品多语言里改英文名。若要求 App 固定按中文请求，需要另外核实 iOS / Android SDK 设置请求语言的接口（本次未改）。

## 验证

服务器上没有 Flutter / Xcode，未编译，未运行测试，也未在真机上验证。只人工复核了 diff，核对了括号配平和 `git diff --check`。需要在本地运行 `flutter analyze`、`flutter test test/app/interaction_log_test.dart test/user_build_test.dart test/debug_log_gate_test.dart`。

## 回滚

撤销本次提交即可。不涉及 DP、接口或持久化数据。
