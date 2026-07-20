# 账号与安全 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“账号与安全”画板。

## 兄弟项目参考

修改密码和忘记密码的验证码校验、提交防重复与成功返回逻辑参考同目录兄弟项目 `D:\Work\learn\flutter` 的 `features/account/presentation/modify_password.dart` 和 `forgot_password.dart`。页面视觉仍完全采用 YSplanter 当前 Figma 和本项目 Design Token。

## Page

- 文件：`lib/src/features/profile/presentation/account_security_page.dart`
- 路由：复用 `AppRoutes.settings`，路径为 `/settings`，以保持“我的”和个人信息页已有入口兼容。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton` 和 `ResponsiveContent`。
- 页面负责手机号提示以及修改密码、忘记密码流程的路由参数组装。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `AccountSecurityCard` | `lib/src/features/profile/presentation/widgets/account_security_card.dart` | 四行半透明账号安全卡片、状态值、箭头和点击区域 |

卡片复用 Design System 的 `AppSettingsList` 与 `AppSettingsTile`。`AppSettingsList` 新增了向后兼容的分隔线缩进和颜色参数，以匹配 24px 设计缩进，没有创建重复公共卡片组件。

## Model 结构

模型文件：`lib/src/features/profile/models/account_security_page_model.dart`

- `AccountSecurityPageModel`：脱敏手机号、登录密码状态与忘记密码说明。
- `AccountSecurityPageModel.fromUser`：把 `AppUser` 转换为页面展示模型，并对 11 位手机号进行中间四位脱敏。

## 交互与路由

- 手机号：当前 Repository 没有修改手机号接口，点击后明确提示“手机号修改功能暂未开放”，不伪造本地保存。
- 登录密码、修改密码：进入现有 `PasswordPage` 的“修改密码”模式，账号预填且成功后返回账号安全页。
- 忘记密码：进入现有验证码重置模式，成功后回到登录页。
- `PasswordArguments` 新增标题与成功返回策略，默认行为仍与原忘记密码入口兼容。

## 尺寸适配与测试

- 375 × 812 为设计基准，卡片宽度 335px、单行高度 61px、左右边距 20px。
- 320 × 568 紧凑视口支持纵向滚动，最后一行始终可达。
- Widget 测试覆盖 Figma 内容、两种密码导航参数、手机号提示和紧凑视口。

## 校验状态

- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 109 项测试。
