# 触觉感知 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma“触觉感知”画板与 `docs/UI/触觉感知.png`。

## Page

- 文件：`lib/src/features/devices/presentation/touch_settings_page.dart`
- 路由：`AppRoutes.touchSettings`，路径为 `/devices/touch`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent` 和 Design System 错误状态。
- Page 从指定设备读取触摸互动设置，将开关和灵敏度操作交给 `FlowerpotState.updateSetting`。
- Slider 拖动时只预览数值，拖动结束后再同步设备；互动关闭时仍允许预设灵敏度，与设计稿状态一致。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `TouchSettingsCard` | `presentation/widgets/touch_settings_card.dart` | 组合触觉页面的状态、说明、开关和灵敏度参数 |
| `DeviceSensitivitySettingsCard` | `presentation/widgets/device_sensitivity_settings_card.dart` | 听觉与触觉页面共用的半透明互动开关及 Slider 卡片布局 |
| `DeviceSettingOrbitIllustration` | `presentation/widgets/setting_orbit_illustration.dart` | 多个设备感知页面共用的同心光晕插画，根据枚举绘制手掌爱心等图标 |

卡片复用 `AppSurfaceCard`，颜色、字体、圆角和间距使用 Design System Token；交互使用 Material 3 `Switch` 与 `Slider`。

## Model 结构

模型文件：`lib/src/features/devices/models/touch_settings_page_model.dart`

- `TouchSettingsPageModel.fromSettings` 将 `DeviceControlSettings` 转为触摸互动开关、0–100 的灵敏度、已启用/已禁用状态和设计说明文案。
- 页面保存 Slider 的临时预览值和两个独立更新状态；设备数据仍由状态层维护。

## 图片资源策略

页面没有嵌入或裁切 Figma 截图。顶部轨道、圆点、手掌和爱心图形使用矢量绘制，可在不同屏幕密度下清晰缩放。

## 交互与路由

- 设备设置页的“触觉感知”行进入本页，不再打开旧控制 Bottom Sheet。
- 触摸互动开关调用 `touchInteraction` 功能点（DP 112）。
- 传感器灵敏度调用 `touchSensitivity` 功能点（DP 113）。
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
