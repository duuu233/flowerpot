# 显示设置 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“显示”画板与 `docs/UI/显示.png`。

## Page

- 文件：`lib/src/features/devices/presentation/display_settings_page.dart`
- 路由：`AppRoutes.displaySettings`，路径为 `/devices/display`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent` 和 Design System 错误状态。
- 页面读取指定设备的显示设置，并通过 `FlowerpotState.updateSetting` 同步自动屏幕亮度功能点。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `DisplaySettingsCard` | `presentation/widgets/display_settings_card.dart` | 半透明主卡片、自动亮度状态、开关、分隔线和说明文案 |
| `DeviceToggleSettingsCard` | `presentation/widgets/device_toggle_settings_card.dart` | 显示与震动设置页面共用的单开关卡片布局 |
| `DeviceSettingOrbitIllustration` | `presentation/widgets/setting_orbit_illustration.dart` | 显示、听觉、触觉和震动页面共用的矢量轨道插画 |

卡片复用 `AppSurfaceCard`、颜色、字体、圆角与间距 Token；开关使用 Material 3 `Switch`，没有复制公共开关组件。

## Model 结构

模型文件：`lib/src/features/devices/models/display_settings_page_model.dart`

- `DisplaySettingsPageModel.fromSettings`：将 `DeviceControlSettings.autoBrightness` 转换为开关值、已开启/已关闭状态和 Figma 说明文案。

## 图片资源策略

页面未嵌入或裁切 Figma 截图。中心亮度图形没有独立设计资源，使用矢量 `CustomPainter` 绘制，可随屏幕密度清晰缩放。

## 交互与路由

- 设备设置页的“显示”行进入本页，不再打开旧控制 Bottom Sheet。
- 自动屏幕亮度开关调用现有 `autoBrightness` 功能点（DP 109）；更新期间禁用开关，失败时使用统一错误提示。
- 手动亮度（DP168）2026-10-28 起：拖动 300ms 节流、串行只发最近值、同值不重发，松手立即补发最终值；松手后滑块停在最终值，
  直到本次成功下发几次就收到几次 DP168 真实上报（`FlowerpotState.dpReportRevision`）且最新值等于最终值、稳定 500ms，
  才改显示设备状态；最长 5 秒，失败立即恢复。
- 找不到设备时复用 `AppErrorView`。

## 尺寸适配与测试

- 375 × 812 为设计基准：主卡宽 335px、高约 339px、左边距 20px，卡片顶部对应截图 117px 位置。
- 320 × 568 紧凑视口支持纵向滚动，说明文案始终可达。
- Widget 测试覆盖 Figma 文案和尺寸、紧凑视口、DP 同步、缺失设备状态及设置入口路由。

## 校验状态

- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 164 项测试。
