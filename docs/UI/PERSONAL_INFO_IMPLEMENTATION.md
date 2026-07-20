# 个人信息 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“个人信息”画板。

## 兄弟项目参考

头像选择、本地即时预览、昵称校验和资料状态同步参考同目录兄弟项目 `D:\Work\learn\flutter` 的 `features/account/presentation/profile_page.dart`；退出登录确认与接口在途防重复参考其设置页。页面视觉仍完全采用 YSplanter 当前 Figma 和本项目 Design Token。

## Page

- 文件：`lib/src/features/profile/presentation/profile_page.dart`
- 路由：`AppRoutes.profile`，路径为 `/profile`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton` 和 `ResponsiveContent`。
- Page 负责头像选择、昵称编辑、账号安全导航、账号 ID 复制和退出登录。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `PersonalInfoCard` | `lib/src/features/profile/presentation/widgets/personal_info_card.dart` | 四行半透明资料卡、头像、资料值、编辑图标、箭头和分隔线 |
| `PersonalInfoLogoutButton` | 同上 | 页面底部退出登录操作 |

头像复用 Design System 的 `AppAvatar`，资料容器复用 `AppSurfaceCard`，没有创建重复的公共头像或卡片组件。

## Model 结构

模型文件：`lib/src/features/profile/models/personal_info_page_model.dart`

- `PersonalInfoPageModel`：昵称、脱敏手机号、账号 ID 和头像路径。
- `PersonalInfoPageModel.fromUser`：把 `AppUser` 转换为页面展示模型，并对 11 位手机号进行中间四位脱敏。

## 图片与资源

- 已选择的本地头像通过 `FileImage` 展示，HTTP(S) 头像通过 `NetworkImage` 展示。
- 没有头像时复用 `AppAvatar` 的品牌色文字占位。
- 未裁切或引用 Figma 截图中的头像。

## 交互

- 点击头像从系统相册选择图片，本地即时预览并调用现有 `updateProfile` 保存。
- 点击昵称打开 Material 3 编辑弹窗，空昵称不可提交。
- 点击手机号进入现有账号与安全设置入口。
- 点击账号 ID 复制到剪贴板并显示提示。
- 点击退出登录先二次确认，成功后清空导航栈并返回登录页；接口处理期间操作自动禁用。

## 尺寸适配与测试

- 375 × 812 为设计基准，资料卡宽度 335px、单行高度 61px、左右边距 20px。
- 320 × 568 紧凑视口支持纵向滚动，退出登录始终可达。
- Widget 测试覆盖 Figma 内容、昵称保存、退出登录导航和紧凑视口。

## 校验状态

- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 104 项测试。
