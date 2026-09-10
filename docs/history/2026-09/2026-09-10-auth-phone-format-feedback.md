# 手机号格式校验补上反馈：toast + 输入框下面的提示行

> 文档类型：Historical Change Record
> 日期：2026-09-10
> 环境：SSH（无 Flutter/Dart 工具链）
> 分支与起始版本：main / ef11017
> 范围：`lib/src/features/auth/presentation/`（登录、注册、找回密码三页 + 新增 `widgets/auth_field_error.dart`）
> 当前权威文档：`AI_CONTEXT.md`；上一轮 `docs/history/2026-09/2026-09-09-verification-code-phone-format.md`

## 背景与目标

反馈：2026-09-09 加的手机号格式校验**没有给用户任何反馈**。那一轮的做法是「号码不合法就把
『获取验证码』按钮置灰」——按钮点不动、也不说话，用户不知道是自己号码写错了还是页面坏了。
产品口径：用 toast 提示，或者像表单那样在输入框下面写一行提示，都可以。

## 变更内容

新增 `widgets/auth_field_error.dart`：`AuthFieldError`，输入框下面那行红色提示（图标 + 文案），
`message` 为 null 时不占位置。三页共用。

三页（`auth_page.dart` 登录、`register_page.dart` 注册、`password_page.dart` 找回密码）同一套改法：

- 账号输入框接上 `FocusNode`，新增 `accountTouched` 标记：**失焦一次**、或**点过按钮**之后才开始
  报错。`_accountError` 据此算出那行提示，号码改对了自己消失。
- 新增 `_rejectInvalidAccount()`：号码不合法时**同时**给 toast 和那行常驻提示，返回 true 让调用方
  当场 return。`_sendCode` 的兜底校验改走它。
- **「获取验证码」按钮不再按号码格式置灰**，只在「正忙」和「倒计时中」置灰。
- 登录 / 注册 / 重置密码的提交动作也补上账号格式校验（原来只判空），不再把一个必然被拒的号码
  送到后端去换一句带 `APP-invalid_input` 前缀的红字。
- 三个私有输入框组件（`_LoginField` / `_RegisterField` / `_PasswordField`）加 `focusNode` 与
  `errorText` 两个入参，内部由 `SizedBox(56)` 改成 `Column(胶囊 + AuthFieldError)`。

## 关键决策

- **按钮改回可点，是这次的关键**。置灰按钮是上一轮「不让短信发出去」的手段，但它同时堵死了唯一
  能给用户回话的入口——点不动就没有点击事件，toast 永远不会出现。改成照常可点、在
  `_sendCode` 里挡下来：**短信仍然不会发出去**（`_rejectInvalidAccount` 在调 `sendCode` 之前
  return），但用户拿得到一句话。
- **两种反馈都给，不是二选一**。toast 是「你刚点了什么，我当场回你」，几秒就没；输入框下面那行
  是「到底哪儿不对」，留着直到改对。产品说两种都行，实际上它们回答的是不同的问题。
- **不是边打字边报红**。第一个数字输进去就说「格式不对」是噪音。触发条件是「失焦一次」或
  「点过按钮」——即用户认为自己填完了的那一刻。
- 提示行画在胶囊**外面**，不走 `InputDecoration.errorText`：那会把提示塞进 56 的固定高度里，
  把胶囊本身压扁。
- 找回密码页的账号可能是手机也可能是邮箱，文案按 `region` 取（`请输入正确的 11 位手机号` /
  `请输入正确的邮箱`），与该页原有 toast 文案一致。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK**，`dart format`、`flutter analyze`、`flutter test`
  均未执行。改动经逐行通读，四个文件过了自写的 Dart 感知括号配平检查。
- 测试改动（**未运行**）：`test/features/auth/auth_page_test.dart`
  - 旧用例「位数不够时按钮 `onPressed` 为 null」**已作废**，改写为「点得动 → 给 toast + 那行提示
    → 不发短信 → 号码补对后提示自己消失」；
  - 新增「手机号框失焦时就把格式提示画出来」（输入中不报、焦点挪走才报）。

## 未完成项与风险

- 需在有 SDK 的机器复跑 analyze / test，并在真机上确认那行提示出现时页面不会把底部按钮顶出屏幕
  （三页都在 `SingleChildScrollView` 里，理论上只是变长）。
- 注册页与找回密码页**没有新增用例**，只有登录页覆盖到；三页改法相同，风险主要在版式。
- 上一轮的输入过滤（`digitsOnly` + 11 位）保持不变，没有放宽。
