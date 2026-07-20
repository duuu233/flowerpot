# 帮助中心 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“帮助中心”画板。

## 兄弟项目参考

公共 FAQ 逻辑和交互参考同目录兄弟项目 `D:\Work\learn\flutter` 的 `features/guide/presentation/guide_page.dart`：使用 FAQ ID 集合维护展开状态、允许条目独立展开/收起，并保证长列表可纵向滚动。本页面的背景、卡片、图标、排版和默认首项展开状态仍以 YSplanter 当前 Figma 为准，没有复制兄弟项目 UI。

## Page

- 文件：`lib/src/features/profile/presentation/help_page.dart`
- 路由：`AppRoutes.help`，路径为 `/help`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton` 和 `ResponsiveContent`。
- Page 通过 FAQ ID 的 `Set<String>` 管理多项展开状态，并把切换事件传递给展示 Widget。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `HelpCenterFaqList` | `lib/src/features/profile/presentation/widgets/help_center_faq_list.dart` | 半透明圆角 FAQ 卡片、问题行、答案容器、展开动画和问号气泡图标 |

页面复用 `AppSurfaceCard`、Design Token 和公共页面骨架。问号气泡是帮助中心特有图形，使用 Flutter `CustomPainter` 绘制并保留在 Profile Feature 内。

## Model 结构

模型文件：`lib/src/features/profile/models/help_center_model.dart`

- `HelpCenterPageModel`：FAQ 列表和初始展开 ID 集合。
- `HelpCenterFaqItem`：稳定 ID、问题和答案。
- `HelpCenterPageModel.figma`：当前画板的六项本地展示数据；后续接入 FAQ 接口时可由 Repository 数据转换生成。

## 图片与资源

- 页面不需要位图资源。
- 问号气泡通过 `CustomPainter` 绘制，不裁切或引用 Figma 截图。

## 交互

- 首项按 Figma 画板默认展开。
- 点击任意问题独立切换展开状态，可同时展开多个问题。
- 展开箭头由向右平滑旋转为向下，答案区域使用尺寸动画。
- 页面内容超过可用高度时可纵向滚动。

## 尺寸适配与测试

- 375 × 812 为设计基准，内容最大宽度 375px，左右边距 20px。
- 320 × 568 紧凑视口保持完整滚动与点击能力。
- Widget 测试覆盖 Figma 内容、首项展开、多项独立展开/收起及紧凑视口滚动。

## 校验状态

- 局部 Dart Analyze：通过，0 个问题。
- 全量 `dart analyze lib test`：通过，0 个问题。
- 帮助中心 Widget Test：通过，3 个测试全部成功。
- 全量 `flutter test`：通过，100 个测试全部成功。
