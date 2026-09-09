# 代码审核：移除调试台与体验模式，收口发布前的安全与竞态问题

> 文档类型：Historical Change Record
> 日期：2026-09-09
> 环境：work（`27bbbd9`）→ ssh（本文件与文档收尾）
> 分支与起始版本：main / 38c71f0 → 27bbbd9
> 范围：网络层、状态层、配网与搜索页、登录与「我的」页、Android / iOS 平台配置、测试基建
> 当前权威文档：`AI_CONTEXT.md`、`docs/RELEASE_READINESS_REVIEW.md`、`docs/CODE_REVIEW_HANDOFF.md`

## 背景

`docs/CODE_REVIEW_HANDOFF.md` 记录的审核轮次：按 `RELEASE_READINESS_REVIEW.md` 收口发布前问题，移除涂鸦 SDK 调试台与体验模式，让 App 只走真实数据。代码改动在 work 电脑上作为 `27bbbd9` 提交并推送；本文件在 ssh 端补齐，同时完成 Active 文档的口径修复。

## 已完成（`27bbbd9`，74 个文件 / +926 / −2167）

- **调试台与体验模式整体移除**：`lib/src/features/devtools/`（998 行的联调页）、`lib/src/core/config/debug_tools_config.dart`、`lib/src/features/preview/`、`AppRoutes.tuyaDebug` 及登录页 / 「我的」页的入口全部删除；`MockTuyaRepository`（405 行）从产品代码搬到 `test/support/mock_tuya_repository.dart`，另分出 `test/support/plant_catalog.dart`、`test/support/fixture_backend.dart`。产品包里不再有任何 Mock 数据通路。
- **S1 明文回落关闭**：`ApiConfig` 默认值改为正式源站 `https://api.yikaltd.com`，`validateBaseUrl` 只接受 HTTPS 源站（带路径 / 查询 / 用户信息或非 https 直接抛错）；Android 的 `network_security_config.xml` 与 Manifest 引用、iOS `Info.plist` 的 ATS 例外一并删除。
- **写请求不再重试**：`ApiClient.postJson` 的 `retryTransportErrors` 默认改为 `false`（GET 仍重试），避免超时重发造成重复提交。
- **旧会话资料迟到**：`ApiSession` 引入 `revision`，`ApiClient` 在发请求前取快照、回来后 `_ensureSession(revision)` 校验，跨登录的迟到响应不再写进新会话。
- **配网销毁通知**：设备搜索页改用 `Timer` 管理 45 秒窗口并全程 `mounted` 保护，页面销毁后不再有回调打到已卸载的 State。
- 新增 `test/core/network/api_safety_test.dart`（故障注入回归）与 `test/flutter_test_config.dart`。

## 本次（ssh）补齐

- **静态自检**（无 Flutter SDK 时能做的部分，全部通过）：
  - 全仓测试文件没有「测试声明写在 `main()` 之外」的语法问题；
  - 38 个引用 `MockTuyaRepository` 的测试文件都已 import `test/support/mock_tuya_repository.dart`；`PlantCatalog` / `FixtureBackend` 同样没有漏 import；
  - 产品代码里已无 `MockTuyaRepository`、`StaticPreviewConfig`、`DebugToolsConfig`、`enterDemo`、`_temporaryBaseUrl` 的残留引用；
  - 2026-09-09 早些时候在 ssh 端完成的功能（`useHome` / `useHomeTag` / `FirmwareUpdate` / `deviceLoadError` / `prepareForPairing` / `sessionDiagnostics` / `_handleBackendSessionExpired` / `isValidAccount`）在 `27bbbd9` 之后全部仍在。
- **Active 文档口径修复**（`AI_CONTEXT.md`）：启动开关与源站段落、`ActionResult.code` 段落、目录表、设备列表段落里「联调页共用 `reloadDevices()`」等措辞、第 117 行的「联调工具」条目、第 3/4/5 条约定、以及 2026-09-03 的临时地址条目与 2026-09-05 的评审结论条目，全部按当前源码改写。

## 仍未关闭

- **S2**：`git ls-files` 仍能看到 `assets/Android_SDK1/security-algorithm/security-algorithm-1.0.0-beta.aar`。移出跟踪会影响所有克隆与分支，且按审核文档需要同时评估供应商侧是否要重发组件，本轮未动。
- **S3**：`ApiClient._clientQuery` 仍把 `userToken` 放进 `/Client/` 请求的 URL 查询（请求头也带），令牌仍存 `SharedPreferences`。去掉查询参数要先与后端确认只认鉴权头，属于跨端契约变更。
- 一小时掉登录的**后端侧**根因（见 `2026-09-09-backend-session-expiry.md`）。

## 验证结果

- **本机（ssh）没有 Flutter/Dart SDK、Android SDK、Xcode**：`flutter analyze`、`flutter test` 未执行，两端桥接与 release 包均未编译。handoff 里记的「基线 49 issues」是 work 端的数字，本轮无法复核。
- 本次改动只有文档与静态检查，没有代码变更。

## 未完成项与风险

- **必须在有 Flutter SDK 的机器上跑一次 `flutter analyze` + `flutter test`**，确认 `27bbbd9` 那次大范围删除与测试基建搬迁之后基线是干净的；这是 handoff「本轮待验证」里唯一还没做的一项。
- iOS 需要 macOS/Xcode 编译验证；配网与 OTA 需要真实设备。
- release 包的 Manifest / Info.plist 与抓包结果尚未核对，S1 只在源码层面确认。
