# 多语言框架落地，配套七项首页 / 设置改动

> 文档类型：Historical Change Record
> 日期：2026-09-08
> 环境：SSH 开发机（无 Flutter/Dart 工具链）
> 分支与起始版本：main / 9dfc52d
> 范围：`lib/src/shared/l10n/`（新增）、`lib/src/app/flowerpot_app.dart`、`lib/src/state.dart`、首页顶栏与模型、设备设置 / 其他设置 / 行为 / 纪念日编辑、新增「自动检测植物」与「休眠模式」两页、路由与对应测试
> 当前权威文档：`AI_CONTEXT.md`

## 背景与目标

产品本轮七条：① 首页顶栏中间改成设备名称；② 参照相册 APP 做多语言，先简中 + 英文，框架要能扩到 18 种；③「自动检测植物」按 LED 设置那样做成独立页；④「其他设置」去掉「系统文件更新」「修复系统文件」；⑤ 编辑纪念日未选日期时拦一下；⑥ 编辑纪念日的文字输入框样式对齐设计稿；⑦ 补「休眠模式」（DP 151/152），入口放「行为」页，版式照割草机的雨淋设置。

## 变更内容

### 多语言框架（②）

- 新增 `lib/src/shared/l10n/app_language.dart`：`AppLanguage` 枚举，每项带 `code`（持久化 / 接口 / `Locale` 都用它）和 `label`（语言自己的名字）；`fromCode` 兼容 `zh-Hans`、`en-US` 这类历史取值；`fallbacks` 定义缺译文时的回落链，最终一定落到简体中文。**加一门语言 = 加一个枚举值 + 在文案表里补条目**，缺的条目自动回落，不会白屏。
- 新增 `lib/src/shared/l10n/app_l10n.dart`：`AppLocalizationsScope`（InheritedWidget，由 `MaterialApp.builder` 挂在 Navigator 之上）+ `AppL10n` 文案目录，取文案写成 `t({AppLanguage.zh: '...', AppLanguage.en: '...'})`。做法与相册 APP 的 `AppL10n` 一致，区别是相册用位置参数 `_pick(zh, en, ja)`，这里用 Map——18 种语言下位置参数会失控。
- `FlowerpotState.language` 暴露 `AppLanguage`（`languageCode` 仍在，后端接口继续用它）；设置页的语言列表改成由 `AppLanguage.values` 生成，以后加语种不用改那一页。
- 覆盖范围：本轮改动涉及的页面（设置、自动检测植物、休眠模式、编辑纪念日的新提示、首页养护卡）已走目录；**其余页面仍是硬编码中文**。
- **没有引入 `flutter_localizations`**：本机没有 Flutter SDK，跑不了 `flutter pub get`，改 pubspec 会让别人拉下来直接构建失败。因此 Material / Cupertino 内建文案（长按菜单、返回键无障碍标签）目前仍是英文，与改动前一致，没有回退。要跟随语言就加这个依赖并跑一次 `pub get`，同时给 `MaterialApp` 补 `localizationsDelegates` 和 `supportedLocales`。

### 页面改动

- **①** `HomeHeader` 增加 `title`：非空时正中显示设备名称（长名省略号收尾），为空仍是品牌标识，所以「未添加设备」那一屏没变。名字由 `HomeDashboardModel.deviceName` 提供。
- **③** 设置页的「自动检测植物」由行内开关改为跳页行（显示已开启 / 已关闭），新增 `PlantDetectionSettingsPage`，用与 LED 设置同一个 `DeviceToggleSettingsCard`；`DeviceSettingsFunctionList` 的开关行支持、`DeviceSettingsMenuItem.toggle` 与设置页的 `_setToggle` 一并删除（已无使用者）。`DeviceSettingSymbol` 新增 `plant`。
- **④** 「其他设置」删除「系统文件更新」「修复系统文件」两行、中间那条红色说明条 `_SystemFileNotice`，以及它们各自只弹一句「暂未开放」的处理函数和回调参数。
- **⑤** 编辑纪念日保存前校验日期：`_entry.date == null` 时提示「请选择日期」（走文案目录）并中断保存。固定和自定义两类都要日期，所以不区分。
- **⑥** 文字输入框：左右边距对齐上面的标题 / 日期框（16），上下由 14/10 改成 16/12，输入区高度 92 → 104，正文与占位字号 16 → 17（与标题框一致）；三个输入框的圆角统一由 `AppRadius.card`(16) 改为 12——设计稿上它们是同一个形状，16 在这种矮框上偏圆。
- **⑦** 新增 `StandbySettingsPage`：一张卡，上半是开关（DP 151，即时下发）和说明，下半是「延迟时间」时 / 分双滚轮（`ListWheelScrollView`，选中格有高亮带），页面底部「保存」写 DP 152。滚轮取值实时收进 1–180 分钟（`TuyaConfig.standbyDelayMin/Max`），越界时把滚轮拨回边界值。入口是「行为」页新增的一行，显示当前开关状态。

## 关键决策

- **休眠开关即时下发、延迟时间由「保存」写**：滚轮每滚一格就发一条 DP 只会把指令堆在链路上；开关则沿用本 App 其他设置页「拨完就生效」的既有交互。雨淋设计稿上是一个「保存」管两者，这里是有意的差异。
- **文案表分两处**：界面 chrome 走 `AppL10n`；设备状态文案（需水 / 光照 / 温度 / 湿度）留在 `TuyaStatusCopy`——它是按功能点枚举组织的数据表，两处都按语言取。
- 编辑纪念日的圆角改了三个框而不是只改内容框：设计稿上三者同形，只改一个会更不一致。
- 英文文案为本轮撰写，需产品或英文母语者复核。

## 外部操作

无。

## 验证结果

- **本机没有 Flutter / Dart 工具链，`flutter analyze` 与 `flutter test` 都没跑**，只做静态复核，不宣称通过。
- 新增测试：`plant_detection_settings_page_test.dart`（渲染、开关写 DP 163、设置页跳页且不再有行内开关）、`standby_settings_page_test.dart`（版式、开关写 DP 151、保存写 DP 152 = 30、设备缺失错误态、行为页入口跳转）；`home_scene_test.dart` 增加顶栏设备名称用例；`device_other_settings_page_test.dart` 改为断言两行已下线。
- 未补测试：编辑纪念日的日期校验、滚轮滚动后的取值与钳位（滚轮用例需要驱动 `ListWheelScrollView`，没有 SDK 无法确认写法）。

## 未完成项与风险

1. 全套 `flutter analyze` / `flutter test` 待在有 SDK 的机器上补跑；本轮改动面大（新增 2 页 + 框架 + 5 处改造），务必先跑再验机。
2. 多语言只覆盖本轮页面，其余页面切英文仍显示中文；Material 内建文案要跟随语言需另加 `flutter_localizations`。
3. 休眠模式没有真机验证：DP 151/152 的下发链路此前没有页面用过。
4. 编辑纪念日的样式按设计稿和上方输入框推导，未在真机比对；「中间白色部分内容过小」按「输入区偏矮 + 字号比标题小」处理，若产品指的是别的，看截图再调。
5. 首页顶栏改成设备名称后，原来的品牌标识只在未绑定设备时出现，需产品确认这是预期。

## 回滚或恢复

七项互相独立，可按文件粒度 revert：多语言框架集中在 `lib/src/shared/l10n/` 与 `flowerpot_app.dart` 的 `builder`；两页新增各自独立成文件与路由；其余是页面内的局部改动。
