# 关于 YSplanter Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“关于YSplanter”画板。

## 兄弟项目参考

检查更新的状态组织、异常处理原则和版本说明展示方式参考同目录兄弟项目 `D:\Work\learn\flutter` 的 `features/settings/presentation/update_boltstar_page.dart`。页面视觉仍完全采用 YSplanter 当前 Figma 和本项目 Design Token。

## Page

- 文件：`lib/src/features/profile/presentation/about_page.dart`
- 路由：`AppRoutes.about`，路径为 `/about`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent` 和 `showAppBottomSheet`。
- Page 负责组合品牌区、版本信息卡片、检查更新提示和版本说明弹层。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `AboutBrandLockup` | `lib/src/features/profile/presentation/widgets/about_brand_lockup.dart` | Logo 占位、YSplanter 字标和品牌标语 |
| `AboutVersionCard` | `lib/src/features/profile/presentation/widgets/about_version_card.dart` | 当前版本、检查更新和版本说明三行信息卡片 |

版本卡复用 Design System 的 `AppSettingsList` 与 `AppSettingsTile`，版本说明复用公共 Material 3 Bottom Sheet。

## Model 结构

模型文件：`lib/src/features/profile/models/about_page_model.dart`

- `AboutPageModel`：应用名称、品牌标语、当前版本、更新状态与版本说明。
- `AboutPageModel.current()`：提供与当前 `pubspec.yaml` 一致的 `1.0.0` 展示数据。

## 图片与资源

项目现有 iOS 和 Android 启动图标仍是 Flutter 默认图标，不能作为 YSplanter 正式品牌资源。当前页面使用代码绘制的植物、花盆和 “YS” 语义 Logo 占位，没有裁切 Figma 截图；取得正式品牌 Logo 后只需替换 `AboutBrandLockup` 的 Logo 层。

## 交互

- 检查更新：当前项目尚无 App 版本服务接口，因此显示模型中的“已是最新版本”状态，不伪造网络请求或下载进度。
- 版本说明：打开公共 Bottom Sheet，展示当前版本和功能说明，可点击“知道了”关闭。

## 尺寸适配与测试

- 375 × 812 为设计基准，品牌区与版本卡按 Figma 的大留白关系排列。
- 320 × 568 紧凑视口自动收紧顶部间距并支持纵向滚动。
- Widget 测试覆盖 Figma 内容、更新提示、版本说明弹层和紧凑视口。

## 校验状态

- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 164 项测试。
