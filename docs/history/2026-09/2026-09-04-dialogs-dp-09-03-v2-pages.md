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

- **纪念日**（`memorial_page.dart`）：固定的生日、结婚纪念日两行 + 自定义条目，`N/10条` 计数、左滑删除、虚线「新增纪念日」。
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

## 回滚或恢复

改动分布在上列文件与新增文件中。回滚弹窗改造需要同时恢复 `app_confirm_dialog.dart`、`app_option_dialog.dart` 和三处调用点；回滚功能点表需要同时回退 `tuya_config.dart`、`tuya_models.dart`、`tuya_repository.dart`、`state.dart` 与 `tuya_config_test.dart`。新增页面与路由可单独删除，`AppRoutes` 里去掉三条常量和对应分支即可。
