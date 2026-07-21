# 登录密码 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“登录密码”画板与 `docs/UI/登录密码.png`。

## Page

- 文件：`lib/src/features/profile/presentation/login_password_page.dart`
- 路由：`AppRoutes.loginPassword`，路径为 `/login-password`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent` 与 `FilledButton`。
- 页面管理两次密码输入、独立明文切换、8–20 位长度校验、两次输入一致性校验和保存状态。

## Widget 拆分

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `LoginPasswordAccountCard` | `lib/src/features/profile/presentation/widgets/login_password_account_card.dart` | 登录方式说明与当前账号脱敏展示 |
| `AccountPasswordFormCard` | `lib/src/features/profile/presentation/widgets/account_password_form_card.dart` | 登录密码与修改密码页共用的密码输入、图标、分隔线与独立可见性控制 |
| `LoginPasswordAdviceCard` | `lib/src/features/profile/presentation/widgets/login_password_advice_card.dart` | Figma 密码设置建议提示 |

三个区域复用 Design System 的 `AppSurfaceCard`、`AppIconBadge`、颜色、圆角、间距和字体 Token；密码表单同时与“修改密码”页共用，没有创建重复组件。

## Model 结构

模型文件：`lib/src/features/profile/models/login_password_page_model.dart`

- `LoginPasswordPageModel`：保存脱敏账号、密码最小/最大长度和页面建议文案。
- `LoginPasswordPageModel.fromAccount`：将手机号、邮箱或普通账号转换为安全展示文本；11 位手机号按 `138****5678` 形式脱敏。

## 交互与路由

- “账号与安全”页的“登录密码”行进入本页；“修改密码”和“忘记密码”继续使用验证码重置页，不改变已有流程。
- 密码输入默认隐藏，两个眼睛按钮分别控制各自字段。
- 当前 `TuyaRepository` 未提供已登录账号设置初始登录密码的接口。页面完成本地规则校验后会明确提示“登录密码设置功能暂未开放”，不伪造保存；`onSave` 回调保留给后续真实接口接入。

## 尺寸适配与测试

- 375 × 812 为设计基准：内容宽 335px、左右边距 20px、信息卡 90px、表单卡 153px、主按钮 50px。
- 320 × 568 紧凑视口支持纵向滚动，保存按钮始终可达。
- Widget 测试覆盖 Figma 文案、账号脱敏、紧凑视口、独立密码可见性、长度与一致性校验，以及账号安全页路由参数。

## 图片资源策略

页面未裁切或嵌入 Figma 截图。盾牌、锁、提示气泡使用 Material 图标，闭眼状态使用轻量 `CustomPainter` 还原截图中的无斜杠闭眼图标。

## 校验状态

- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 164 项测试。
