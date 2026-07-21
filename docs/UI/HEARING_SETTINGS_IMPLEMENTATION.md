# 听觉感知 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma“听觉感知”画板与 `docs/UI/听觉感知.png`。

## Page

- 文件：`lib/src/features/devices/presentation/hearing_settings_page.dart`
- 路由：`AppRoutes.hearingSettings`，路径为 `/devices/hearing`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent` 和 Design System 错误状态。
- Page 从指定设备读取听觉设置，将声音开关和灵敏度操作交给 `FlowerpotState.updateSetting`。
- Slider 拖动时只预览数值，拖动结束后再同步设备，减少连续 DP 写入。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `HearingSettingsCard` | `presentation/widgets/hearing_settings_card.dart` | 半透明主卡片、声音互动状态、开关、说明文案、灵敏度数值和 Slider |
| `DeviceSensitivitySettingsCard` | `presentation/widgets/device_sensitivity_settings_card.dart` | 听觉与触觉页面共用的互动开关及灵敏度卡片布局 |
| `DeviceSettingOrbitIllustration` | `presentation/widgets/setting_orbit_illustration.dart` | 多个设备感知页面共用的同心光晕插画，根据 `DeviceSettingSymbol` 绘制对应图标 |

卡片复用 `AppSurfaceCard`，颜色、字体、圆角和间距使用 Design System Token；开关和滑杆使用 Material 3 `Switch` 与 `Slider`。

## Model 结构

模型文件：`lib/src/features/devices/models/hearing_settings_page_model.dart`

- `HearingSettingsPageModel.fromSettings` 将 `DeviceControlSettings` 转为声音互动开关、0–100 的灵敏度、开关状态文案和设计说明文案。
- 页面保存 Slider 的临时预览值和两个独立更新状态；业务数据仍由设备状态层维护。

## 图片资源策略

页面没有嵌入或裁切 Figma 截图。顶部轨道、圆点和声波图形使用矢量 `CustomPainter` 绘制，可在不同屏幕密度下清晰缩放，并与显示页面复用视觉结构。

## 交互与路由

- 设备设置页的“听觉感知”行进入本页，不再打开旧控制 Bottom Sheet。
- 声音互动开关调用 `soundInteraction` 功能点（DP 110）。
- 传感器灵敏度调用 `soundSensitivity` 功能点（DP 111），开关关闭时 Slider 随之禁用。
- 更新失败使用统一错误提示，找不到设备时复用 `AppErrorView`。

## 尺寸适配与测试

- 375 × 812 为设计基准：主卡宽 335px、高 425px、左边距 20px，卡片顶部对应截图 117px 位置。
- 320 × 568 紧凑视口支持纵向滚动，灵敏度 Slider 始终可达。
- Widget 测试覆盖 Figma 文案和尺寸、紧凑视口、两个 DP 同步、缺失设备状态及设置入口路由。

## 所属批次与校验状态

- 所属批次：账户密码、显示与设备感知设置页面批次。
- 页面级 Widget 测试：通过，共 6 项。
- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 164 项测试。
