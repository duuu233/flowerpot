# 设备设置页面 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，归入 UI 开发批次 1，是该批次的第 3 个页面。完整回归测试将在本批次累计约 5 个页面后统一执行。

## Page

- 文件：`lib/src/features/devices/presentation/device_settings_page.dart`
- 路由：`AppRoutes.deviceSettings`，路径为 `/devices/settings`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton` 和 `ResponsiveContent`。
- 顶部分享按钮继续调用现有设备分享接口并复制分享链接。
- 页面找不到设备时使用 Design System 错误状态组件。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `DeviceSettingsSummaryCard` | `presentation/widgets/device_settings_summary_card.dart` | 设备占位图、名称、陪伴天数和更多入口 |
| `DeviceSettingsFunctionList` | `presentation/widgets/device_settings_function_list.dart` | 功能设置标题和七项设置入口 |
| `DeviceSettingsControlSheet` | `presentation/widgets/device_settings_control_sheet.dart` | 显示、听觉、触觉、振动、行为和其他设置的控制弹层 |

设备卡复用 `AppSurfaceCard`、`AppStatusChip` 和 `AppDevicePlaceholder`；设置列表复用 `AppSettingsList`、`AppSettingsTile` 和 `ToggleSettingsTile`。

原首页设备色块占位已提升为 Design System 的 `AppDevicePlaceholder`，供首页和设备设置页共同使用，没有建立跨 Feature 重复组件。

## Model 结构

模型文件：`lib/src/features/devices/models/device_settings_page_model.dart`

- `DeviceSettingsPageModel`：设备名称、植物名称、陪伴天数和功能设置集合。
- `DeviceSettingsMenuItem`：设置项标题、类型和当前状态值。
- `DeviceSettingsMenuKind`：植物、显示、听觉、触觉、振动、行为和其他设置。
- `DeviceSettingsPageModel.fromDevice`：把 `SmartPlanterDevice` 和 `DeviceControlSettings` 转换成页面展示模型。

## 图片占位

- 缺少独立盆栽设备图片时使用 `AppDevicePlaceholder(hasPlant: true)`。
- 不引用或裁切 Figma 截图。
- 正式素材到位后仅替换占位图片层。

## 页面交互

- 返回按钮 → 上一页面。
- 分享按钮 → 生成并复制设备分享链接。
- 更多 → 设备名称、植物、固件和设备 ID。
- 选择植物 → 植物选择页面。
- 显示、听觉感知、触觉感知、震动设置、行为、其他设置 → 对应控制 Bottom Sheet。
- 控制项继续调用现有 `FlowerpotState.updateSetting`、维护和配网能力。

## 尺寸适配

- 375 × 812 为设计基准。
- 内容最大宽度为 375，并在宽屏 iPhone 上居中。
- 320 × 568 紧凑视口使用纵向滚动。

## 批次校验状态

- 页面测试用例已建立。
- 完整静态分析、双尺寸和全量 Flutter Test 在 UI 批次 1 完成约 5 页后统一执行。
