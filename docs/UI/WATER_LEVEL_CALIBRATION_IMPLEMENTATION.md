# 水位传感器校准 Flutter 实现说明

本流程遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 中“水位传感器校准”的四张连续画板，并作为“其他设置”页内的 Dialog 状态实现，不新增独立主路由。

## Page

- 入口文件：`lib/src/features/devices/presentation/device_other_settings_page.dart`
- 页面继续使用 `AppPageScaffold`、`AppPageHeader`、`ResponsiveContent`、`AppSurfaceCard` 和统一设置列表样式。
- 点击“水位传感器校准”打开四步向导；Page 把每一步接到 `FlowerpotState.calibrateWaterLevel(deviceId, step)`（DP 140）与 `cancelWaterLevelCalibration`（`step5`）。
- **下发时机是“卡片出现”**：弹窗一打开就发 `step0`，之后每点一次“下一步”先发下一张卡片的 step，成功才切卡；失败时保留当前步骤并用 Design System 的错误 Snackbar 反馈。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `WaterLevelCalibrationDialog` | `lib/src/features/devices/presentation/widgets/water_level_calibration_dialog.dart` | 四步弹窗布局、步骤切换、提交状态、底部操作、正式步骤图和资源失败占位 |
| `AppStepIndicator` | `lib/src/design_system/widgets/data_display/app_step_indicator.dart` | 复用公共四步进度展示，并修正步骤数字插值及未激活数字颜色 |

弹窗采用 Material 3 `Dialog`，最大宽度 327px、圆角 20px、半透明遮罩和 56px 双操作栏，还原设计稿的层级、分割线与按钮颜色。

## Model 结构

模型文件：`lib/src/features/devices/models/water_level_calibration_model.dart`

- `WaterLevelCalibrationModel`：流程标题与四步静态展示数据。
- `WaterLevelCalibrationStepModel`：单步说明、插图类型、无障碍语义及底部操作文案。
- `WaterLevelCalibrationVisual`：倒空水仓、首次加水、再次加水和完成四种插图状态。

Widget 只消费页面 Model；设备维护调用仍由 Page 负责。

## 图片与占位策略

- 四个步骤分别使用 `AppAssets.waterCalibrationRemoveInnerPot`、`AppAssets.waterCalibrationAdd30ml`、`AppAssets.waterCalibrationAddSecond30ml` 和 `AppAssets.waterCalibrationComplete` 对应的正式图片资源。
- 步骤图通过 `Image.asset` 加载；资源加载失败时只显示带对应中文 `Semantics` 的简单语义色块占位，不再回退到复杂 `CustomPainter` 插画。
- 未裁切、未引用四张 Figma 截图，也未把设计截图注册为 Flutter Asset。

## 交互与状态

1. 第一步：移出植物内胆并倒空水仓（弹窗出现时已下发 `step0`）。
2. 第二步：向水仓倒入 30mL 水（进入时下发 `step1`）。
3. 第三步：再次倒入 30mL 水（进入时下发 `step2`）。
4. 第四步：展示校准完成状态（进入时下发 `step3`），“关闭”和“完成”都只退出向导，不再下发。

前三步的“取消”下发 `step5` 后关闭弹窗，第四步的“关闭”不发（四步已走完）；下发期间禁用两个操作并显示品牌色进度指示器，避免重复发送。

## 尺寸适配与测试

- 375 × 812 为设计基准，Dialog 最大宽度 327px、最大高度 420px。
- 320 × 568 紧凑视口自动压缩可用宽度，说明文字降至 18px，插图按可用区域等比缩放。
- Widget 测试覆盖四步文案与操作流、完成后关闭，以及 320 × 568 紧凑视口无溢出。

## 校验状态

- 局部 Dart Analyze：通过，0 个问题。
- 全量 `dart analyze lib test`：通过，0 个问题。
- 相关 Widget Test：通过，9 个测试全部成功。
- 全量 `flutter test`：通过，97 个测试全部成功。
