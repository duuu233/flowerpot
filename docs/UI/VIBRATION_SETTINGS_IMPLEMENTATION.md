# 震动设置 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma“震动设置”画板与 `docs/UI/震动设置.png`。

## Page

- 文件：`lib/src/features/devices/presentation/vibration_settings_page.dart`
- 路由：`AppRoutes.vibrationSettings`，路径为 `/devices/vibration`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent` 和 Design System 错误状态。
- Page 从指定设备读取震动设置，并通过 `FlowerpotState.updateSetting` 同步设备功能点。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `VibrationSettingsCard` | `presentation/widgets/vibration_settings_card.dart` | 组合震动设置页面的标题、状态、说明和开关参数 |
| `DeviceToggleSettingsCard` | `presentation/widgets/device_toggle_settings_card.dart` | 显示与震动设置页面共用的半透明单开关卡片布局 |
| `DeviceSettingOrbitIllustration` | `presentation/widgets/setting_orbit_illustration.dart` | 显示、听觉和震动页面共用的同心光晕插画，通过枚举绘制对应图标 |

卡片复用 `AppSurfaceCard`，颜色、字体、圆角和间距使用 Design System Token；开关使用 Material 3 `Switch`。

## Model 结构

模型文件：`lib/src/features/devices/models/vibration_settings_page_model.dart`

- `VibrationSettingsPageModel.fromSettings` 将 `DeviceControlSettings.vibration` 转为开关值、已启用/已禁用状态和设计说明文案。
- 更新中的临时禁用状态由 Page 管理，设备数据仍由状态层维护。

## 图片资源策略

页面没有嵌入或裁切 Figma 截图。顶部轨道、圆点和倾斜震动图形使用矢量 `CustomPainter` 绘制，可在不同屏幕密度下清晰缩放。

## 交互与路由

- 设备设置页的“震动设置”行进入本页，不再打开旧控制 Bottom Sheet。
- 启动震动开关调用 `vibration` 功能点（DP 114）；更新期间禁用开关，失败时使用统一错误提示。
- 找不到设备时复用 `AppErrorView`。

## 尺寸适配与测试

- 375 × 812 为设计基准：主卡宽 335px、高 339px、左边距 20px，卡片顶部对应截图 117px 位置。
- 320 × 568 紧凑视口支持纵向滚动，说明文案始终可达。
- Widget 测试覆盖 Figma 文案和尺寸、紧凑视口、DP 同步、缺失设备状态及设置入口路由。

## 所属批次与校验状态

- 所属批次：账户密码、显示与设备感知设置页面批次。
- 页面级 Widget 测试：通过，共 5 项。
- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 164 项测试。
