# 手机验证码登录的「登录注册一体」补齐

> 文档类型：Historical Change Record
> 日期：2026-09-03
> 环境：SSH（无 Flutter/Dart 工具链，无 codegraph）
> 分支与起始版本：main / 43f9e3c
> 范围：`lib/src/core/backend/`、`lib/src/state.dart`、相关测试与文档
> 当前权威文档：[`../../../AI_CONTEXT.md`](../../../AI_CONTEXT.md) 第 3、5 节；[`../../PRD_IMPLEMENTATION.md`](../../PRD_IMPLEMENTATION.md)

## 背景与目标

真实短信链路联调时，用手机号 + 验证码登录报 `接口-403 邮箱不存在`。

定位：这条文案是 APP 后端 `/Client/User/userLoginVerifyCode` 的 `retCode` 403 + `retMsg`，被 `FlowerpotState._tagged` 打上「接口」来源后原样显示。含义是该手机号在后端没有账号——文案本身是后端沿用了海外邮箱那一套，与邮箱无关。

对照 `assets/智能花盆功能列表.xlsx` 与 Swagger：登录页文案与 `auth_page_test.dart` 都写着「未注册手机将自动创建账户 / Registration happens implicitly on first login」，但 `FlowerpotState.login` 只调了登录接口，未注册就到此为止。缺的是「登录注册一体」这一步。

## 变更内容

- `AppBackendRepository.loginWithCode` 的契约改为「登录注册一体」：`HttpAppBackendRepository` 捕获登录失败，命中「账号不存在」时用同一条验证码调 `/Client/User/userRegisterMobile` 补注册。注册接口返回的会话字段（`userToken` / `userNo` / `tuYaPwd`）与登录接口一致，因此不再登录第二次。
- 新增 `_isAccountMissing`：只认 `retCode` 403 且文案命中「不存在 / 未注册 / not exist / not registered」。后端把「验证码错误」和「账号不存在」压在同一个 403 上，只有文案能区分；文案一改这里退回直接报错，而不是把验证码错误误判成未注册去重复注册。
- 新增 `_generatedPassword()`：注册接口要求密码，验证码登录没有让用户设密码这一步，自动注册时生成 16 位随机密码占位（`Random.secure`）。
- `BackendAuthAccount.registered` 标出会话是注册接口建立的；`registerMobile` 一律置 true。`FlowerpotState.login` 据此把提示从「登录成功」换成「已为你创建账号并登录」。

## 关键决策

- 补注册放在 REST 仓库而不是 `FlowerpotState`：判定依据是 `retCode` 与后端文案，属于 REST 边界的知识；状态层只负责把「新建了账号」说给用户听。
- 先登录后注册，不先查存在性：Swagger 只有 `chkUserEmailNotExist`（邮箱），手机号没有对应的查询接口。
- 自动注册的密码不告诉用户：密码登录入口当前由 `LoginEntryConfig.passwordLogin` 关着，用户要用密码登录得走「忘记密码」重设。

## 外部操作

- 读取 `https://api.yikaltd.com/v2/api-docs`（同时读了写死的临时地址 `http://120.25.227.36:8601`，两份契约一致，123 条路径），核对 `UserLoginVerifyCodeApiIn` / `UserRegisterMobileApiIn` / `UserInfoDetailApiOut` 字段。
- 用两个未注册手机号 + 任意验证码调 `userLoginVerifyCode`，均返回 `{"retCode":403,"retMsg":"验证码错误"}`（HTTP 200）。据此判断验证码在账号查找之前判，「邮箱不存在」出现在验证码已经判过之后。未发送真实短信，未执行写接口。

## 验证结果

- 新增 `test/core/backend/app_backend_repository_test.dart` 两例：403 +「邮箱不存在」触发补注册（校验请求顺序、复用验证码、`password == confirmPassword` 且为 32 位小写 md5、`registered` 为 true）；403 +「验证码错误」不补注册、异常照常抛出。
- 新增 `test/state_backend_integration_test.dart` 一例：`registered` 为 true 时登录提示为「已为你创建账号并登录」。
- 本机没有 Flutter/Dart 工具链，`dart format`、`flutter analyze`、`flutter test` 均未运行。改动只做了静态复核，行宽按 80 列人工核过。

## 未完成项与风险

- 验证码复用未在真机验证：若后端在验证码判过之后即作废，补注册会以「验证码错误」失败。最稳妥的做法是后端在 `userLoginVerifyCode` 内部自动建号，客户端这条回落即可删掉。
- 「账号不存在」靠文案识别，建议后端给一个独立的 `retCode`；同时那句「邮箱不存在」用在手机号登录上是错的，值得让后端改成「手机号未注册」。
- `resetPassword` 国内链路仍走涂鸦（`FlowerpotState.resetPassword`），没有接后端的 `/Client/User/resetPassword`，自动建号的用户重设密码这条路还不通。
- `https://api.yikaltd.com` 本次核验可用，`ApiConfig._temporaryBaseUrl` 写死的 IP 及配套的 Android network-security-config、iOS ATS 例外可以按其 TODO 回滚，本次未动。

## 回滚或恢复

`git checkout -- lib/src/core/backend/ lib/src/state.dart test/` 即可回到只调登录接口的行为。
