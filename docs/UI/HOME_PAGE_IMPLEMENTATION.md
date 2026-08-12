# 首页 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`。

当前归入 UI 开发批次 1；“未添加植物”场景测试用例已经补充，完整回归测试将在本批次累计约 5 个页面后统一执行。

## 页面文件

- `lib/src/features/home/presentation/home_page.dart`
- 基于 Material 3。
- 复用 `AppPageScaffold`、`ResponsiveContent`、`AppSurfaceCard`、`AppSettingsList`、`AppSettingsTile`、`AppIconBadge` 与 `AppAvatar`。
- 375 × 812 为设计基准，最大内容宽度为 375；小于 360 宽度时自动收紧水平间距，内容高度不足时纵向滚动。
- 已添加植物和未添加植物状态通过 `AppPageBackground.home` 全屏铺设 `assets/images/bg01.png`；登录后无设备状态使用纯白背景与 `setting_orbit_background.png`。
- 首页不显示底部导航，通过头像和首页操作项进入后续页面。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `HomeHeader` | `presentation/widgets/home_header.dart` | 右侧用户头像、无头像占位、YSplanter 品牌标题 |
| `HomePlantOverview` | `presentation/widgets/home_plant_overview.dart` | 植物设备占位、环境指标、陪伴天数和电量 |
| `HomeCareBanner` | `presentation/widgets/home_care_banner.dart` | 今日养护信息 |
| `HomeQuickActions` | `presentation/widgets/home_quick_actions.dart` | 定制动画、电池状态、设置入口 |
| `HomeHelpCard` | `presentation/widgets/home_help_card.dart` | 使用帮助入口列表 |
| `HomeUnplantedContent` | `presentation/widgets/home_unplanted_content.dart` | 已绑定设备但尚未添加植物时的空植物场景 |
| `HomeOrbitDecoration` | `presentation/widgets/home_orbit_decoration.dart` | 首页不同场景共用的设备轨道装饰 |
| `AppDevicePlaceholder` | `design_system/widgets/data_display/app_device_placeholder.dart` | 首页与设备页面共用的有植物、无植物设备色块占位 |
| `HomeCompanionBadge` | `presentation/widgets/home_companion_badge.dart` | 首页不同场景共用的陪伴天数和电量摘要 |

局部 Widget 仅承载首页特有的布局和语义。卡片、头像、图标容器、设置列表等通用能力继续由 `design_system` 提供，没有建立重复公共组件。

## Model 结构

模型文件：`lib/src/features/home/models/home_dashboard_model.dart`

- `HomeDashboardModel`：首页聚合展示数据。
- `HomeMetricData`：单项环境指标。
- `HomeActionData`：单个快捷操作。
- `HomeMetricKind`：需水、光照、温度、湿度。
- `HomeActionKind`：定制动画、电池、设置。
- `HomeDashboardModel.fromDevice`：把 `SmartPlanterDevice` 转换为页面展示模型；设备为空时提供 Figma 占位数据，便于后续 API 接入。
- `HomeDashboardScene.withCompanionSummary`：显示“已陪伴天数 / 电量”胶囊，对应第一张首页设计图。
- `HomeDashboardScene.withoutCompanionSummary`：隐藏胶囊并收紧下方间距，对应 `首页-已添加植物-1.png`。
- `HomeDashboardScene.withoutPlant`：显示设备已绑定但尚未添加植物的空状态，对应 `首页-未添加植物.png`。
- 空植物场景的标题、说明和按钮文案由 `HomeDashboardModel` 提供，便于后续服务端配置或本地化。

两个场景共用同一个 `HomePage`。第二场景通过 `HomePage(scene: HomeDashboardScene.withoutCompanionSummary)` 构建，不复制页面和 Widget。

## 资源占位规则

已添加植物与未添加植物首页使用正式全屏背景 `bg01.png`，无设备首页使用 `setting_orbit_background.png`。用户没有本地或网络头像时使用 `profile_avatar_icon.png`，今日养护使用 `select_plant_icon.png`。后续页面遇到缺失图片资源时仍不裁切设计截图，获得正式素材后仅替换图片层，不改变页面结构。

## 页面跳转

- 头像 → 个人资料。
- 环境指标、电池状态 → 对应的状态详情页。
- 光照状态指标 → 光照状态与 DLI 页面。
- 定制动画 → 动画管理。
- 设置 → 设备设置。
- 使用指南 → 帮助中心。
- 没有已连接设备时，设备相关入口显示信息提示。
- 未添加植物场景中的“添加植物” → 植物选择页面。
