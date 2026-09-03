# 统一弹窗样式、并入 09-03 功能点表、补 v2 页面与 LED 设置

> 文档类型：Historical Change Record
> 日期：2026-09-04
> 环境：SSH（无 Flutter/Dart 工具链、无 Android SDK）
> 分支与起始版本：main / ab5eb96（工作区已含同日的配网搜索改动）
> 范围：`design_system`、`lib/src/tuya`、设备设置动线、`docs/UI/v2`
> 当前权威文档：`AI_CONTEXT.md`、`docs/TUYA_SDK_SETUP.md`

## 背景与目标

四件事一起做：

1. 弹窗还在用 Material `AlertDialog`，和其余页面完全不是一套视觉；要按兄弟项目 `/pgdata/pg/dh/flutter` 的 `AppDialog` 改写，配色换成 YSplanter 自己的品牌青。
2. 涂鸦后台导出了新的功能点表 `assets/智能花盆test(yciq4kssu1fv8umn)_09_03.xlsx`，需要核对并并入新增项。
3. `docs/UI/v2/智能花盆ysplanter/` 里是新增页面，要落进产品动线并结合新功能点接上真实调用。
4. 新增一个「LED设置」页，单开关，版式照 `docs/UI/震动设置.png`。

## 变更内容

### 1. 弹窗

- 新增 `lib/src/design_system/widgets/dialogs/app_dialog.dart`：`AppDialog` / `showAppDialog` / `showAppNoticeDialog` / `showAppInputDialog` / `AppDialogTextField` / `AppDialogButton`，版式对齐参考项目（左侧图标盒 + 标题说明 + 缩进的按钮行、圆角 20、胶囊按钮），确认键改为 `brandPrimary → brandDark` 竖向渐变，破坏性操作只把图标盒换成红色。
- `showAppConfirmDialog` 改成 [AppDialog] 的薄封装（签名不变，新增可选 `icon`）；`showAppOptionDialog` 换成同一套外壳。
- 迁移剩余三处 `AlertDialog`：设备重命名、昵称修改、注销账号；`app_settings_page` 的语言选择由底部弹层改为选项弹窗。仓库里已无 `AlertDialog`。
- 定制设计的两个弹窗（固件更新、水位校准）保持原样——它们本来就是按 Figma 画的。

### 2. 功能点表（09-03 导出）

- `TuyaConfig.productId` 改为 `yciq4kssu1fv8umn`，表来源注释指向新文件。
- 逐行比对：101–150 与 08-20 的表**完全一致**（标识符、类型、范围都没变）；新增 151–160：`standby_switch`、`standby_delay`、`language`、`memorial_set`、`del_photo`、`del_all_photos`、`pin_photo`、`memorial_birthday`、`memorial_wedding`、`op_result`。
- 新增可写设置键 `standby` / `standbyDelay` / `deviceLanguage`（152 的 1–180 在编码时夹边界），以及 `led`（见第 4 节）。
- `DeviceControlSettings` 增 `standbyEnabled` / `standbyDelayMinutes` / `deviceLanguage`；`SmartPlanterDevice` 增 `birthday` / `weddingDay` / `lastOperationResult`（160 的 `<操作>:<对象>:<结果>` 带一个 `lastOperationSucceeded` 解析）。仓库层照常在 `_device` 里解码。
- 新增 `lib/src/tuya/tuya_memorial_codec.dart`：154 的帧编解码、158/159 的 8 字节 ASCII 日期、停用/删除哨兵、raw 的 base64 读 / 十六进制写。

### 3. v2 页面

- **纪念日**（`memorial_page.dart`）：固定的生日、结婚纪念日两行 + 自定义条目，`N/12条` 计数（见「追加」一节）、左滑删除、虚线「新增纪念日」。
- **编辑纪念日**（`memorial_edit_page.dart`）：启用开关、标题（固定条目只读）、日期选择、内容区（固定条目是说明胶囊；自定义分「文字」「图片」两页签，文字带 `0/15` 计数，图片是虚线上传位）。
- **定制动画/图库管理**（`animations_page.dart`）：原来的竖排文件列表换成三列缩略图网格，右上角勾选圈、`6/10` 计数、底部三个圆按钮（上传 / 删除选中 / 取消选择），长按置顶。删除选中时逐张下发 155，全选时改为一次 156；置顶下发 157。
- **配网中的步骤**（`widgets/pairing_progress_view.dart`）：配网期间盖在「连接 Wi-Fi」页上，画「1.连接设备 / 2.发送Wi-Fi信息 / 3.连接云端」，状态来自新增的 `FlowerpotState.pairingStage`，底部「取消配网」调 `cancelPairing`。
- **时段编辑弹窗**（`widgets/schedule_slot_dialog.dart`）：两根滑条一次改完开始与结束并实时显示时长，替换「行为」页原先两个独立的系统时间选择器。
- 新增公共 `AppDashedBorder`，替换动画页里的私有虚线画笔，纪念日和图库共用。

### 4. LED 设置

- `led_settings_page.dart` + `LedSettingsPageModel`，单开关，复用 `DeviceToggleSettingsCard` 与 brightness 轨道插画。
- 设置页功能列表加「LED设置」和「纪念日」两行；这两行没有切图，`_LeadingIcon` 用同尺寸 Material 图标顶上。

### 5. 路由与测试

- 新增 `/devices/led`、`/devices/memorial`、`/devices/memorial-edit`。
- 新增 `test/tuya/memorial_codec_test.dart`、`test/features/devices/led_settings_page_test.dart`、`test/features/devices/memorial_page_test.dart`；`test/tuya_config_test.dart` 按 60 条/PID 更新并补 151–160 与 LED 复用 117 的断言；`behavior_settings_page_test.dart` 的注入点由 `timePicker` 改为 `slotEditor`。

## 关键决策

- **LED 走 117**。09-03 的表里没有独立的 LED 功能点，而 117「显示屏幕亮度开关」就是设备唯一的亮灯开关，按它的名字讲这本来就是个开关（显示页把它讲成「自动亮度」是更宽松的解读）。所以 LED 页和显示页共用 117、状态同步；固件补了独立功能点后改 `TuyaConfig.setting['led']` 一行即可。**这条需要产品确认。**
- **自定义纪念日的清单存在 App 本地**。DP 154 是 upsert 通道，设备不回报整份集合，App 是唯一知道有哪些 id、用户给它们起了什么名字的地方。因此这份清单持久化到 `SharedPreferences`，并且**退出登录不清**——清掉会在设备上留下无法命名也无法删除的孤儿条目。它按设备 id 存，设备 id 属于硬件而不是账号。
- **raw 下发用十六进制**。上报按 base64 解（沿用历史 DP 的既有实现），下发按涂鸦 SDK 的惯例写十六进制串。本仓库此前没写过任何 raw 功能点，这条是约定不是验证过的事实。
- **配网进度是覆盖层不是新路由**。`pairViaHotspot` 是一次 await 走完的，中途换页面就没人在等那个 Future，成功/失败也没地方跳。
- **时段编辑改成一个弹窗**。原先开始和结束是两个独立的系统时间选择器，改完开始才发现时段只剩十分钟或跨了午夜；v2 的版式一次改完两端并显示时长。
- **图库全选删除走 156 而不是逐张 155**：一次下发比几十条 DP 可靠。

## 外部操作

无。未连真机、未提交、未推送。

## 验证结果

- 静态复核：新增/修改的 Dart 文件全部过了一遍自写的 Dart 感知括号配平检查；枚举新增值后逐个排查了穷举 switch（`DeviceSettingsMenuKind` 的 `_assetFor` 已补）；`showAppMessage` 在 `shared` 与 `design_system` 各有一份且签名不同，`app_settings_page` 因此只按文件引入两个弹窗函数而没有整包导入 `design_system`。
- **未执行** `dart format`、`flutter analyze`、`flutter test`、任何平台构建：本机 PATH 里没有 Flutter/Dart。新增和改写的测试一次都没跑过。

## 未完成项与风险

- 全部改动需要在有工具链的机器上补跑 `dart format lib test`、`flutter analyze lib test`、`flutter test`。预计会有若干 `prefer_const_constructors` 一类的 lint 提示需要顺手清掉。
- LED 与显示共用 117 需要产品/固件确认；确认前两页的开关是联动的。
- raw 功能点（154/155/157/158/159）的下发编码、DP 154 的帧被固件如何解析、160 回执的实际取值，全部未在真机验证。
- 图片型纪念日目前把 URL 原样写进帧：App 只做了本地选图和预览，没有上传通道把它变成设备可访问的 URL（和 142/143/144 是同一个未决问题）。
- `showDatePicker` 会显示英文月份和按钮：项目没有接 `flutter_localizations`，`MaterialApp` 只设了 `locale` 没设 delegates。这是既有限制，本次没有一并处理。
- `docs/UI/v2/智能花盆ysplanter/编辑周四时段2.png` 画的是带「每周计划」和底部导航的排程页，功能点表里并没有每周计划相关的 DP，因此只取了它的**时段编辑弹窗**版式用在「行为」页，没有实现每周计划。
- `docs/UI/v2/割草机/` 整套是另一个产品的设计，本次未处理。

## 追加（同日第二轮）

### 纪念日计数上限

产品口径更正：列表满员是 **12 条 = 10 条自定义 + 生日 + 结婚纪念日**，不是 10 条。新增
`TuyaMemorialCodec.maxEntries`（= `maxCustomEntries + 2`），页面计数改成按整份列表算
（固定的两条也占位）；「新增纪念日」的可用性仍然只看自定义那 10 条，因为固定的两条既加不了
也删不掉。测试断言由 `0/10条` 改为 `2/12条`。

### OTA

先回答功能点的问题：**OTA 不是功能点**。09-03 的表里和固件相关的只有 148 `firmware_version`
和 149 `hardware_version` 两个只上报的版本号；升级本身走涂鸦 SDK 的 OTA 接口
（Android `newOTAInstance`/`getOtaInfo`/`startOta`，iOS `getFirmwareUpgradeInfo`/`upgradeFirmware`），
两端桥接此前已经接好，事件通道也已在推 `{status, percent, message}`。所以这一轮不是"接入"，
而是补它缺的那几块：

- **Android 桥接持有 OTA 实例**（真正的 bug）。`newOTAInstance` 每次新建一个 `IThingOta`，
  而升级要跑几分钟；原来 `startOta` 一返回就把引用丢了，App 侧没有任何强引用，注册进去的监听
  代理随时可能被回收，进度和成败回调就再也不来——界面表现为进度停在某个百分比不动。改为按
  deviceId 缓存实例（`otaInstances`），升级出终态或 `releaseDeviceListeners()` 时调 `onDestroy` 放掉。
- **中断逃生**。涂鸦不保证一定回终态（设备掉电、掉线、校验失败之后可能什么都不再来）。新增
  `FlowerpotState.otaStalled`（10 分钟无事件）与 `clearOtaProgress`，「其他设置」页在卡住时
  弹确认框让用户重新检查，而不是永远被挡在「固件正在升级中」上。
- **失败文案**。`checkFirmware` 抛 `TuyaException` 时原来直接把异常对象插进字符串，界面上是
  `固件检查失败：Instance of 'TuyaException'`；改为显示 `error.message`。
- 新增 `test/state_ota_test.dart`：覆盖「没有 OTA 功能点」这条事实、发起后版本号不能提前改、
  进度事件驱动、success 才采用新版本、failed 保留旧版本、卡住后可清除重试。

这几条同样**没有跑过** `flutter analyze` / `flutter test`，Kotlin 侧也没编译过。真机上还需要
确认：`IThingOta.onDestroy` 在当前 SDK 版本里存在（不存在时按"该版本不需要显式释放"吞掉）、
以及涂鸦后台的「OTA 能力」是否已开通——没开通的话 `getOtaInfo` 会直接报错，和固件版本无关。

### OTA（同日第三轮：小红点与两端补齐）

补的是产品要的那条动线：**拿到新版本号就点个小红点，用户点一下，App 通知涂鸦让设备升级**。
App 全程不和设备直接说话——问版本、下发升级、收进度，三步都是对着涂鸦 SDK。

- **状态**。`FlowerpotState` 新增 `_availableFirmware`：`checkFirmware` 拿到的版本号和设备当前
  版本比过之后才记进去（涂鸦在「已最新」时可能回 null、空串或把当前版本原样回来，三种都不算
  新版本）。配套 `hasFirmwareUpdate` / `availableFirmwareFor`，以及静默版
  `refreshFirmwareUpdate`——失败一声不吭，因为它是页面自己发起的，用户此刻并没有要求检查固件。
  收到 `success` 事件时连同版本号一起把红点熄掉。
- **红点在哪**。「设置」页的**其他设置**行（`DeviceSettingsMenuItem.badge` → 新增的
  `AppNoticeDot`）和「其他设置」页的**固件版本更新**行。两页都在 `initState` 里静默查一次，用户
  不点进去也能看见。首页那排「动画 / 电量 / 设置」没有动——那要改首页模型和卡片，超出这次范围。
- **点击**。已经知道版本号就不再问第二遍，直接弹「检查更新」，确认后 `upgradeFirmware` 通知涂鸦
  给设备下发升级。只有「升级似乎已中断 → 重新检查」那条路径会强制重新问云端。
- **进度百分比被转圈顶掉了**（真正的 bug）。`_SettingsRow` 的 `loading` 和 `value` 是二选一，而
  原来写的是 `loading: updatingFirmware || ota?.status == running`——升级期间永远在转圈，那句
  「升级中 42%」一次也没显示过。改成只有"正在问云端"那几百毫秒才转圈。
- **iOS 桥接的实例同样没被持有**（和上一轮修的 Android 是同一个 bug）。
  `ThingSmartDevice.delegate` 是 weak、SDK 也不持有实例，`startFirmwareUpgrade` 里临时 new 出来
  的那台方法一返回就没人引用了，`firmwareUpgradeProgress` 和成败回调都不会来。改为
  `otaDevice(_:)`：`watched` 里有就复用，否则新建、设 delegate、留在 `upgrading` 里，出终态或
  `releaseDeviceListeners()` 时才放；`checkFirmware` 的两个闭包也显式捕获了 device。
- **测试**。`state_ota_test.dart` 补了红点四例（有新版本、同版本不算新、静默失败不出声但主动检查
  照常抛、success 后熄灭）；`device_other_settings_page_test.dart` 补了红点/无红点两例，并修好一条
  从 08-29 起就和实现对不上的旧断言——它还在期待「点了立即更新版本号就变」，而版本号从那次改动
  起就只在收到 success 事件后才变；`device_settings_page_test.dart` 补了菜单行红点两例。

这一轮同样**没有跑过** `flutter analyze` / `flutter test`：这台机器上没有 Flutter SDK，两端桥接
也没编译过。真机上仍要先确认涂鸦后台的「OTA 能力」已开通。

## 回滚或恢复

改动分布在上列文件与新增文件中。回滚弹窗改造需要同时恢复 `app_confirm_dialog.dart`、`app_option_dialog.dart` 和三处调用点；回滚功能点表需要同时回退 `tuya_config.dart`、`tuya_models.dart`、`tuya_repository.dart`、`state.dart` 与 `tuya_config_test.dart`。新增页面与路由可单独删除，`AppRoutes` 里去掉三条常量和对应分支即可。
