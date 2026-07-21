# 修改密码 Flutter 实现说明

本页面遵循 `docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`，对应 Figma 的“修改密码”画板与 `docs/UI/修改密码.png`。

## Page

- 文件：`lib/src/features/profile/presentation/modify_password_page.dart`
- 路由：`AppRoutes.modifyPassword`，路径为 `/modify-password`。
- 使用 Material 3、`AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent` 与 `FilledButton`。
- 页面管理原密码、新密码、确认密码的独立显隐、8–20 位长度校验、两次输入一致性校验、保存状态和忘记密码导航。

## Widget 拆分与复用

| Widget | 文件 | 职责 |
| --- | --- | --- |
| `AccountPasswordFormCard` | `lib/src/features/profile/presentation/widgets/account_password_form_card.dart` | 登录密码与修改密码页共用的半透明密码卡片、字段行、分隔线及闭眼图标 |

该组件由原登录密码页的表单卡抽取，两个页面共享同一份字段尺寸、图标容器、文字样式与可见性按钮，没有复制公共 UI。

## Model 结构

模型文件：`lib/src/features/profile/models/modify_password_page_model.dart`

- `ModifyPasswordPageModel`：保存新密码最小/最大长度，并提供长度校验。
- `ModifyPasswordArguments`：保存当前账号与登录区域，用于“忘记密码？”跳转时预填正确账号。

## 交互与路由

- “账号与安全”页的“修改密码”行进入本页。
- “忘记密码？”进入现有 `PasswordPage` 验证码重置流程，成功后返回登录页。
- 当前 `TuyaRepository` 未提供“原密码 + 新密码”的已登录改密接口。页面完成本地校验后明确提示“修改密码功能暂未开放”，不伪造保存；`onChangePassword` 回调保留给后续真实接口接入。

## 尺寸适配与测试

- 375 × 812 为设计基准：内容宽 335px、左右边距 20px、三行密码卡 230px、主按钮 50px。
- 320 × 568 紧凑视口支持纵向滚动，确认按钮始终可达。
- Widget 测试覆盖 Figma 文案和尺寸、紧凑视口、三字段独立显隐、输入校验、忘记密码路由与账号安全页入口。

## 图片资源策略

页面未裁切或嵌入 Figma 截图。锁图标使用 Material 图标，闭眼状态复用账号密码表单组件中的轻量 `CustomPainter`。

## 校验状态

- `dart analyze lib test`：通过，无静态分析问题。
- `flutter test --reporter compact`：通过，共 164 项测试。
