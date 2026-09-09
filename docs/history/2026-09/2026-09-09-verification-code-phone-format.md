# 发验证码前校验手机号格式

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：SSH
> 分支与起始版本：main / 2fa56d0
> 范围：`lib/src/features/auth`（登录、注册、找回密码三页与 `AuthValidator`）
> 当前权威文档：`AI_CONTEXT.md`

## 背景与目标

反馈：登录界面发送手机验证码要校验手机号格式。

## 排查

`FlowerpotState.sendCode` 本来就走 `_normalizeAccount` → `AuthValidator.account`，格式不对会以 `APP-invalid_input 手机号格式不正确` 失败，所以短信不会真的发出去。缺的是**界面这一层**：

- 手机号输入框只设了 `keyboardType: TextInputType.phone`，**没有输入过滤**——那套键盘上还有 `+ - ( ) *`，粘贴还能带进字母、空格，位数也不限；
- 「获取验证码」按钮只在 `busy` 或倒计时期间禁用，**号码不合法照样可点**，用户点完才收到一个带 `APP-invalid_input` 前缀的红色提示。

## 变更内容

- `AuthValidator` 新增 `isValidAccount(value, region)`：只判断格式、不抛异常，与 `account()` 共用同一组正则（手机 `^1[3-9]\d{9}$`、邮箱），避免界面放行、提交却被拦。
- 登录页 `auth_page.dart`：手机号框加 `FilteringTextInputFormatter.digitsOnly` + `LengthLimitingTextInputFormatter(11)`；`accountController` 加监听，「获取验证码」按钮在号码不合法时禁用；`_sendCode` 里补一道兜底校验（粘贴、输入法直接提交等路径），提示改为「请输入正确的 11 位手机号」。
- 注册页 `register_page.dart`：同样的输入过滤 + 按钮禁用 + 兜底校验。
- 找回密码页 `password_page.dart`：账号框可能是手机也可能是邮箱，**不加数字过滤**，但按当前区域校验后再决定按钮是否可点，并补兜底提示。

## 关键决策

- 校验只做「格式」，不做「号段是否真实存在」：`^1[3-9]\d{9}$` 是与后端、涂鸦一致的口径，再严就会误伤新号段。
- 三页都保留了发送前的兜底校验而不是只靠按钮禁用：验证码短信是要花钱的，不该发出去再靠后端拦。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK**，`flutter analyze` 与 `flutter test` 均未执行。
- 新增用例（未运行，`test/features/auth/auth_page_test.dart`）：位数不够时「获取验证码」的 `onPressed` 为 null、补齐 11 位后可点；输入 `138-0013 8000abc9` 后输入框里只剩 `13800138000`。原有「输入 13800138000 后点获取验证码」的用例不受影响。

## 未完成项与风险

- 需在有 SDK 的机器复跑 analyze/test，并在真机上确认输入法（尤其是第三方输入法粘贴）确实被过滤。
- 海外邮箱注册路径没有改动；找回密码页的邮箱校验沿用原正则，只是多了按钮禁用。
