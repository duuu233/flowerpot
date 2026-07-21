# 行为设置 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma“行为”画板与 `docs/UI/行为.png`。

## Page

- 文件：`lib/src/features/devices/presentation/behavior_settings_page.dart`
- 路由：`AppRoutes.behaviorSettings`，路径为 `/devices/behavior`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent` 和 Design System 错误状态。
- Page 从指定设备读取午休及夜间睡眠设置，负责开关、时间选择和状态更新。
- 时间选择使用 Material 3 `showTimePicker` 并固定为 24 小时格式；跨日结束时间增加“次日”展示前缀。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `BehaviorScheduleCard` | `presentation/widgets/behavior_schedule_card.dart` | 午休或夜间睡眠的状态、开关、说明及时间行布局 |
| `BehaviorTimeRow` | `presentation/widgets/behavior_schedule_card.dart` | 可点击的开始/结束时间行及箭头反馈 |

两张卡片复用 `AppSurfaceCard`，颜色、字体、圆角和间距使用 Design System Token；开关使用 Material 3 `Switch`。

## Model 结构

模型文件：`lib/src/features/devices/models/behavior_settings_page_model.dart`

- `BehaviorSettingsPageModel`：包含午休与夜间睡眠两个日程模型。
- `BehaviorSchedulePageModel`：标题、开关、说明、开始时间、结束时间、状态与跨日标签。
- `BehaviorClockTime`：与 Flutter Widget 无关的 24 小时时间值，负责安全解析和格式化。
- 无效设备时间字符串会回退到设计默认值，避免页面构建失败。

## 图片资源策略

本页面没有图片内容，也没有嵌入或裁切 Figma 截图。背景、卡片和时间行全部使用 Flutter 布局与 Design System 实现。

## 交互与路由

- 设备设置页的“行为”行进入本页，不再打开旧控制 Bottom Sheet。
- 午休开关调用 `napEnabled`（DP 115），时间段调用 `napPeriod`（DP 116）。
- 夜间睡眠开关调用 `nightEnabled`（DP 117），时间段调用 `nightPeriod`（DP 118）。
- 更新期间仅禁用对应日程卡片，另一张卡片仍可操作；失败时使用统一错误提示。
- 找不到设备时复用 `AppErrorView`。

## 尺寸适配与测试

- 375 × 812 为设计基准：两张卡片宽 335px、高 268px、间距 12px，第一张卡片顶部对应截图 117px 位置。
- 320 × 568 紧凑视口支持纵向滚动，夜间结束时间始终可达。
- Widget 测试覆盖 Figma 文案和尺寸、紧凑视口、四个 DP、跨日标签、缺失设备状态及设置入口路由。

## 所属批次与校验状态

- 所属批次：账户密码、显示与设备感知设置页面批次。
- 页面级 Widget 测试：通过，共 8 项。
- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 164 项测试。
