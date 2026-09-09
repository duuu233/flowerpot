# 「用一个小时就掉登录」：后端会话失效不该清掉涂鸦会话

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：SSH
> 分支与起始版本：main / c612166
> 范围：`lib/src/state.dart`、`lib/src/core/network/api_client.dart`
> 当前权威文档：`AI_CONTEXT.md`

## 背景与目标

反馈：登录状态一个小时左右就失效，但后端说 token 是有效的。

## 排查

APP 后端的 token **没有客户端 TTL**：`ApiSession` 把它写进 `SharedPreferences`，不带过期时间，App 里也没有任何一小时量级的定时器。所以"掉登录"只可能是某次后端请求回了 401/406：

- `ApiClient._parse`：`statusCode == 401 || retCode == 401 || retCode == 406` → `session.clear()` 并抛出带 `isAuthError` 的 `ApiException`。这个后端的 `retCode 406` 就是「请重新登录！」。
- `FlowerpotState._run`：`if (error.isAuthError) _clearLocalSession();` —— **把整个本地会话清掉**，包括 `_user`（涂鸦会话）、设备列表、植物与设置缓存。用户于是被弹回登录页。

问题在第二条：设备清单、DP 上报、配网、固件全部走涂鸦 SDK，和 APP 后端的 token 没有任何关系。后端 token 到期（或某一次请求没带上 token）本不该影响这些，却把用户整个踢了出去；而后端只看得到"token 还在表里"，两边对不上。

## 变更内容

- `FlowerpotState._handleBackendSessionExpired`：401/406 时**只** `_backend.clearSession()`，记下原因（来源 + 错误码 + 后端原文）并 `notifyListeners()`，**不再动涂鸦会话和设备列表**。需要后端的功能（图库、植物目录、意见反馈、改昵称）仍各自报「登录状态已失效，请重新登录」。
- 失效原因进现场信息：设备列表页底部那行诊断追加「后端会话：…」，登录成功或退出登录时清空。
- `ApiClient._parse` 在判死会话前打一行日志：`[session] 后端会话失效：<METHOD> <path> → HTTP <code> / retCode <code>`。**只记路径不记 query**，token 不进日志。后端说"token 有效"时，这一行能指出是哪个接口、哪一层判的。

## 关键决策

- 没有做自动续期：App 手里只有涂鸦的 uid/密码（来自后端登录响应），没有后端账号的凭据，续不了后端 token。要自动续期得后端提供刷新接口。
- 没有放宽 401/406 的判定：这两个码确实是「请重新登录」，问题不在识别，在处置范围。

## 外部操作

无。

## 验证结果

- 本机（SSH 开发机）**没有 Flutter/Dart SDK**，`flutter analyze` 与 `flutter test` 均未执行。
- 新增用例（未运行，`test/state_backend_integration_test.dart`）：登录后让后端每次业务调用都回 406，`updateProfile` 失败但 `state.authenticated` 仍为 true、`user` 还在、诊断行里出现「后端会话」。

## 未完成项与风险

- **根因仍在后端**：一小时这个数字像是后端会话/redis 的有效期，而他们查的是 token 表。请拿新版本复现一次，把日志里那行 `[session] 后端会话失效：POST /Client/... → HTTP 200 / retCode 406` 发给后端，能直接定位是哪个接口、什么时候开始 406。
- 若确认后端 token 就是一小时有效期，需要后端给一个刷新接口（或延长有效期），否则用户每小时仍要重新登录一次才能用图库、植物目录这些依赖后端的功能——设备侧不受影响。
