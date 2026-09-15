# 光照状态页面 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，归入 UI 开发批次 1，是该批次的第 4 个页面。页面完成后已随批次执行完整回归测试。

## Page

- 文件：`lib/src/features/devices/presentation/light_status_page.dart`
- 路由：`AppRoutes.lightStatus`，路径为 `/devices/light-status`。
- 首页“光照状态”进入该页面。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`TimeRangeSelector`、`DateRangeNavigator` 和 `MetricChartCard`。
- 日、周、月切换重新读取对应时间范围的光照历史（DP 137/138/139，lux）。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `LightStatusSummaryCard` | `presentation/widgets/light_status_summary_card.dart` | 设备占位、光照等级、说明、lux 和 PPFD |
| `LightDliBarChart` | `presentation/widgets/light_dli_bar_chart.dart` | DLI 柱状图、网格、刻度和时间标签 |

页面继续复用 `AppDevicePlaceholder`、`AppSurfaceCard`、`AppIconBadge`、`CareAdviceCard` 和公共范围选择组件，没有重复实现卡片、日期导航或信息提示。`MetricChartCard` 增加了向后兼容的标题前置图标和文本样式参数，`AppInfoCard` 增加强调式图标布局，供截图中的 DLI 标题和建议卡复用。

## Model 结构

模型文件：`lib/src/features/devices/models/light_status_page_model.dart`

- `LightStatusPageModel`：设备 ID、光照等级、解释、lux、PPFD、DLI 数据和建议。
- `LightStatusPageModel.fromDevice`：把 `SmartPlanterDevice` 传感器数据和历史 DLI 转换成页面展示模型。
- 光照等级及建议由当前照度动态生成，不把 Figma 数字写死到业务页面。

## 数据来源

- lux：`SensorSnapshot.illuminance`。
- PPFD：`SensorSnapshot.ppfd`。
- 光照历史：`FlowerpotState.historyFor(deviceId, SensorMetric.light, range)`，即 DP 137–139 解出的照度（lux）。图表标题「光照强度」、单位 lux，纵轴上限按数据取整刻度。⚠️ 2026-09-15 以前这里读 `SensorMetric.dli`，功能点表没有 DLI 历史 DP，真机上永远空态；设计稿的「DLI（每日光量积分）」要等设备新增 DLI 历史 DP 或产品给定换算口径（见 `docs/PRODUCT_RULES.md` §4.5）。
- 进页面在联调日志记 108/109/110 原始值与 137–139 到货情况（`logStatusDps` / `logHistoryDiagnostics`）。
- 日期前后导航目前调整展示周期；历史接口扩展日期参数后可直接接入指定周期数据。
- PPFD 全链路使用 `double`，保留设备上报的三位小数精度；体验模式数据使用截图中的 305 lux、5.642 μmol/m²/s 及周 DLI 示例。

## 图片占位

- 缺少盆栽设备素材时复用 `AppDevicePlaceholder(hasPlant: true)`，占位组件使用 Flutter `CustomPainter` 绘制叶片、粉色盆体、表情面板和阴影。
- 不引用或裁切 Figma 截图。

## 尺寸适配

- 375 × 812 为设计基准。
- 内容最大宽度为 375，并在宽屏 iPhone 上居中。
- 页面内容可纵向滚动，适配 320 × 568 紧凑视口。
- 图表根据可用宽度动态计算柱宽和标签位置。

## 批次校验状态

- 页面测试覆盖 375 × 812 内容结构与 320 × 568 滚动适配。
- `dart analyze lib test`：通过，0 个问题。
- `flutter test`：通过，17 个测试全部成功（包含光照页真实设备数据与日/周范围切换测试）。
- 回归过程中同时修复了设备设置摘要卡在 320px 宽度下的 8px 标签溢出。
