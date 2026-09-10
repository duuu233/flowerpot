# 登录页只留 toast 提示；toast 宽度改跟屏宽走，短提示不再折行

> 文档类型：Historical Change Record
> 日期：2026-09-10
> 环境：SSH（无 Flutter/Dart 工具链）
> 分支与起始版本：main / c437953
> 范围：`lib/src/features/auth/presentation/auth_page.dart`、`lib/src/shared/widgets/app_toast.dart`、对应用例
> 当前权威文档：`AI_CONTEXT.md`；相关 `docs/history/2026-09/2026-09-10-auth-phone-format-feedback.md`

## 一、登录页去掉输入框下面那行校验提示

产品口径：登录页校验不通过时**有 toast 就够用了**，不要 form 表单那行常驻提示。

同日早些时候给三页都加了「toast + 行内提示」两种反馈；这一轮把**登录页**那行去掉：

- 删掉 `accountFocus`（FocusNode）、`accountTouched`、`_handleAccountFocusChange`、`_accountError`
  与 `AuthFieldError` 的引用——它们全部只服务那行提示。
- `_rejectInvalidAccount()` 保留，只剩「弹 toast + 让调用方 return」。**校验本身一点没松**：
  「获取验证码」照常在发送前挡下不合法号码，短信仍然不会发出去；登录提交也照常校验格式。
- `_LoginField` 去掉 `focusNode` / `errorText` 两个入参，退回单纯的 `SizedBox(56) + TextField`。

**注册页与找回密码页仍保留那行提示**，本轮没动：产品说的是登录页。这两页的表单更长
（账号 / 验证码 / 密码 / 确认密码），toast 弹完就没了，用户回头改的时候没有东西可参照。
要不要一起去掉，等产品一句话。

## 二、toast 宽度：写死 300 → 跟屏宽走

现象：登录页那句「请先阅读并同意用户协议与隐私政策」在 toast 里折成了两行。

算一下就知道为什么这么容易折：气泡 `maxWidth` 写死 300，减去左右内边距 18×2、图标 19、
图标与文字的间距 9，**留给文字的只有 236**；而这句 16 个汉字在 14px 下正好要 **224**——
只差 12px。用户把系统字号调大一档（1.1 倍）就是 246 > 236，必折。

改法：

- `maxWidth` 由写死的 300 改成 `(屏宽 - 32).clamp(260, 380)`。375 的屏上是 343，
  留给文字 284，同一句话有 **60px 富余**，字号放大到约 1.25 倍仍是一行。
- 顺手把左右内边距 18 → 16、图标间距 9 → 8，这 6px 也让给文字。

⚠️ **「一定不折行」做不到**，也不该做：toast 还要显示接口返回的长报错（开发构建里甚至会贴
原始响应）。这次做的是**把常见短提示的余量拉开**，长文案照旧折行 + 限高裁尾。

## 验证结果

- 本机**没有 Flutter/Dart SDK**，`dart format` / `flutter analyze` / `flutter test` 均未执行。
  两个源文件与两个用例文件过了自写的括号配平检查，改动逐行通读。
- 用例改动（**未运行**）：
  - `auth_page_test.dart`：原「两种反馈都要有」改成「只给 toast、`AuthFieldError` 不出现」；
    原「失焦时画出提示」改写为「登录页不画那行提示」（输入中、失焦后都不画）。
  - `app_toast_test.dart` 新增：375 宽的屏上，那句协议提示排版后**高度不超过一行**，且可用宽度
    不小于文本自身宽度。
- **真机未验**：折不折行最终取决于机型字体与系统字号档位，需要在真机上按「系统字号调大一档」
  再看一眼。

## 未完成项与风险

- 注册页 / 找回密码页的行内提示去留待产品确认（见第一节）。
- `AuthFieldError` 仍被那两页使用，组件本身保留。
- toast 宽度上限 380 是拍的：平板 / 大屏上气泡会比以前宽一截，若觉得太宽改这一个数即可。
