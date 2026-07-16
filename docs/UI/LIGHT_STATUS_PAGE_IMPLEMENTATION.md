# 光照状态页面 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，归入 UI 开发批次 1，是该批次的第 4 个页面。完整回归测试将在本批次累计约 5 个页面后统一执行。

## Page

- 文件：`lib/src/features/devices/presentation/light_status_page.dart`
- 路由：`AppRoutes.lightStatus`，路径为 `/devices/light-status`。
- 首页“光照状态”和设备详情“环境光照”统一进入该页面。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`TimeRangeSelector`、`DateRangeNavigator` 和 `MetricChartCard`。
- 日、周、月切换重新读取对应时间范围的 DLI 历史数据。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `LightStatusSummaryCard` | `presentation/widgets/light_status_summary_card.dart` | 设备占位、光照等级、说明、lux 和 PPFD |
| `LightDliBarChart` | `presentation/widgets/light_dli_bar_chart.dart` | DLI 柱状图、网格、刻度和时间标签 |

页面继续复用 `AppDevicePlaceholder`、`AppSurfaceCard`、`AppIconBadge`、`AppInfoCard` 和公共范围选择组件，没有重复实现卡片、日期导航或信息提示。

## Model 结构

模型文件：`lib/src/features/devices/models/light_status_page_model.dart`

- `LightStatusPageModel`：设备 ID、光照等级、解释、lux、PPFD、DLI 数据和建议。
- `LightStatusPageModel.fromDevice`：把 `SmartPlanterDevice` 传感器数据和历史 DLI 转换成页面展示模型。
- 光照等级及建议由当前照度动态生成，不把 Figma 数字写死到业务页面。

## 数据来源

- lux：`SensorSnapshot.illuminance`。
- PPFD：`SensorSnapshot.ppfd`。
- DLI：`FlowerpotState.historyFor(deviceId, SensorMetric.dli, range)`。
- 日期前后导航目前调整展示周期；历史接口扩展日期参数后可直接接入指定周期数据。

## 图片占位

- 缺少盆栽设备素材时复用 `AppDevicePlaceholder(hasPlant: true)`。
- 不引用或裁切 Figma 截图。

## 尺寸适配

- 375 × 812 为设计基准。
- 内容最大宽度为 375，并在宽屏 iPhone 上居中。
- 页面内容可纵向滚动，适配 320 × 568 紧凑视口。
- 图表根据可用宽度动态计算柱宽和标签位置。

## 批次校验状态

- 页面测试用例已建立。
- 完整静态分析、双尺寸和全量 Flutter Test 在 UI 批次 1 第 5 页完成后统一执行。
