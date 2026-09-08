# 首页养护建议改为四条状态轮播，并给这批文案做中英双语

> 文档类型：Historical Change Record
> 日期：2026-09-08
> 环境：SSH 开发机（无 Flutter/Dart 工具链）
> 分支与起始版本：main / 9dfc52d
> 范围：`lib/src/tuya/tuya_status_copy.dart`、`lib/src/features/home/`、`lib/src/features/devices/models/temperature_status_page_model.dart`、`test/features/home/home_scene_test.dart`
> 当前权威文档：`AI_CONTEXT.md`

## 背景与目标

首页「今日养护」原来是一句自己写的总结（`HomeDashboardModel._careMessage`），只看了需水/光照/湿度三条状态，还会出现卡片写「偏湿」、这句写「今天状态良好」的情况。产品要求：这句改成按当前状态读四条状态（需水 107 / 光照 108 / 空气温度 113 / 空气湿度 115）各自的养护建议，做成 5 秒一条的轮播，并且支持多语种。

## 变更内容

- **文案来源统一**：产品给的 12 条文案与 `TuyaStatusCopy` 里已有的中文表逐字一致，直接复用，不再另写一份。
- **中英双语**：`TuyaStatusCopy` 新增 `waterNeedsEn` / `lightingEn` / `airTemperatureEn` / `airHumidityEn` 四张英文表，以及 `waterNeedsCopy(...)` 等按语言查表的方法（`language` 取 `FlowerpotState.languageCode`，只识别 `en` 前缀，其余一律回落简体中文——App 里还有繁体和日文的语言码，但没有对应译文）。
- **首页模型**：`HomeDashboardModel.fromDevice` 增加 `language` 入参；新增 `careTitle`（今日养护 / Today's care）与 `careMessages`（四条建议，顺序与四张卡片一致：需水 → 光照 → 温度 → 湿度）；四张卡片的标题与取值也跟着语言走。原 `careMessage` 字段删除。
- **温度状态**：首页原来只显示温度读数、不判断冷热，现补上 113 的判断；设备没上报时用与温度状态页同一套阈值，阈值上移到 `TuyaStatusCopy.comfortableLowCelsius/HighCelsius`，两处共用一份。
- **轮播组件**：`HomeCareBanner` 由 `StatelessWidget` 改为有状态组件，`Timer.periodic(interval)`（默认 5 秒）切换，`AnimatedSwitcher` 做淡入淡出 + 上移 420ms 过渡；只有一条时不起定时器；文字区固定两行高（36pt），避免长短不一的建议让卡片高度跳动（卡片整体比原来高约 10pt）。

## 关键决策

- **没有引入全局 i18n**。项目至今没有 `flutter_localizations` / `intl` / arb，所有界面文案都是硬编码中文；只有设置页的「语言」开关（zh / en）与 `MaterialApp.locale` 是现成的。本轮按需求范围只给这批状态文案做了双语表，其余界面仍是中文。全局多语种是一次独立迁移（引入 `flutter_localizations` + gen_l10n，把几百条文案搬进 arb），需要单独排期。
- 英文文案由本轮撰写（产品只给了中文），需要产品或英文母语者复核。
- 四条建议按固定顺序轮播，不按「问题优先」排序：产品要的是「分别读取 4 个状态的养护建议」，排序会让用户看不到状态与卡片的对应关系。

## 外部操作

无。

## 验证结果

- **本机没有 Flutter/Dart 工具链，`flutter analyze` 与 `flutter test` 都没跑**，只做静态复核并补了用例，不宣称通过。
- 新增/修改用例（`test/features/home/home_scene_test.dart`）：轮播每 5 秒切换且四条播完回到第一条；`careMessages` 与 `TuyaStatusCopy` 的四条状态文案逐条对齐；`language: 'en'` 时标题、卡片标签与建议都取英文表。

## 未完成项与风险

1. 轮播用例依赖假时钟，需要在有 SDK 的机器上实跑；真机上还要看两行高度在小屏（320pt 宽）是否会截断——长的一条英文建议可能超过两行被省略号截断。
2. 英文文案待产品复核；繁体中文、日文没有译文，会回落中文。
3. 其余界面仍是硬编码中文，切到英文只有首页这块跟着变。

## 回滚或恢复

改动集中在上列文件，`git revert` 即可。只想回到「一句总结」的话，恢复 `HomeDashboardModel._careMessage` 并把 `HomeCareBanner` 换回接收单条 `message` 的无状态版本。
