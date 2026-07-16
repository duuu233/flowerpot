# “我的”页面 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，归入 UI 开发批次 1，是该批次的第 2 个页面。完整回归测试将在本批次累计约 5 个页面后统一执行。

## Page

- 文件：`lib/src/features/profile/presentation/mine_page.dart`
- 路由：`AppRoutes.mine`，路径为 `/mine`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton` 和 `ResponsiveContent`。
- 首页头像入口进入“我的”，页面内“个人信息”进入资料编辑页。
- 375 × 812 为设计基准；内容最大宽度 375，宽屏 iPhone 居中，小屏 iPhone 可纵向滚动。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `MineProfileHeader` | `presentation/widgets/mine_profile_header.dart` | 用户头像、昵称和编辑入口 |
| `MineMenuList` | `presentation/widgets/mine_menu_list.dart` | 七项个人中心菜单及反馈邮箱 |

头像继续复用 `AppAvatar`，编辑按钮复用 `AppIconButton`，菜单容器及列表项复用 `AppSettingsList` 和 `AppSettingsTile`，未建立重复公共组件。

## Model 结构

模型文件：`lib/src/features/profile/models/mine_page_model.dart`

- `MinePageModel`：昵称、头像路径和页面菜单集合。
- `MineMenuItem`：菜单标题、类型和可选尾部文字。
- `MineMenuKind`：个人信息、账号安全、帮助、反馈、隐私、协议和关于。
- `MinePageModel.fromUser`：把 `AppUser` 转换成页面展示模型。

## 图片占位

- 用户已选择并保存本地头像时显示该头像。
- 没有头像资源时使用品牌色圆形和白色用户图标占位。
- 不引用或裁切 Figma 截图。

## 页面跳转

- 返回按钮 → 上一页面。
- 个人信息、昵称编辑按钮、头像 → 个人资料编辑。
- 账号与安全 → 应用设置和账号管理。
- 帮助中心 → 帮助页面。
- 意见反馈 → 使用现有 Snackbar 展示反馈邮箱。
- 隐私政策 → 隐私政策页面。
- 用户协议 → 用户协议页面。
- 关于 YSplanter → 关于页面。

## 批次校验状态

- 页面测试用例已建立。
- 完整 Dart Analyze、375 × 812、320 × 568 和全量 Flutter Test 在 UI 批次 1 完成约 5 页后统一执行。
