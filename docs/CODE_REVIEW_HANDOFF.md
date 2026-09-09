# 代码审核续接

> 状态：代码改动已提交推送；**只剩「跑 analyze/test」这一项**，需要有 Flutter SDK 的机器
> 日期：2026-09-09；环境：work（代码改动）→ ssh（静态自检与文档收尾）
> 分支：main；起始版本 38c71f02062bbaff4cea8c24bf6d6ae344b0dc6f，代码改动 `27bbbd9`
> 用户最新要求：完成并验证后提交当前 main，`git pull --ff-only` 成功后 push（两个仓库）。

## 范围

按 AGENTS.md、AI_CONTEXT.md、docs/README.md 与 RELEASE_READINESS_REVIEW.md 审核代码，移除涂鸦 SDK 调试台与体验模式，应用只使用真实数据，修复有确定依据的问题。正式源站为用户确认的 https://api.yikaltd.com。无线上写操作。

## 已完成

- **代码改动 `27bbbd9`（work 端，74 文件 / +926 / −2167）**：调试台、体验模式、静态预览开关整体移除，`MockTuyaRepository` 搬到 `test/support/`；S1 明文回落关闭（`ApiConfig` 只收 HTTPS、默认正式源站，Android network-security-config 与 iOS ATS 例外删除）；写请求默认不重试；`ApiSession.revision` + `ApiClient._ensureSession` 挡住旧会话迟到响应；设备搜索页改 `Timer` 截止并全程 `mounted` 保护；新增 `api_safety_test.dart` 与 `flutter_test_config.dart`。
- **ssh 端静态自检（全部通过）**：无「测试声明写在 `main()` 之外」；38 个引用 `MockTuyaRepository` 的测试都已 import 新支持文件，`PlantCatalog` / `FixtureBackend` 同样没漏；产品代码无 `MockTuyaRepository` / `StaticPreviewConfig` / `DebugToolsConfig` / `enterDemo` / `_temporaryBaseUrl` 残留；同日早些时候在 ssh 完成的功能（家庭固定、OTA 版本对、设备列表错误态、手机号校验、后端会话隔离等）在 `27bbbd9` 之后全部仍在。
- **文档收尾**：`AI_CONTEXT.md` 的启动开关 / 源站、`ActionResult.code`、目录表、设备列表段落、「联调工具」条目、第 3/4/5 条约定、2026-09-03 临时地址与 2026-09-05 评审结论全部按当前源码改写；新增历史记录 `docs/history/2026-09/2026-09-09-code-review-cleanup.md` 并更新两个索引。

## 待办（按优先级）

1. **在有 Flutter SDK 的机器上跑 `flutter analyze` + `flutter test`**——`27bbbd9` 删除范围大、测试基建整体搬家，基线必须重新确认。handoff 早前记的「49 issues」是 work 端旧数字，ssh 端无 SDK 无法复核。
2. **S2**：`assets/Android_SDK1/security-algorithm/*.aar` 仍被 Git 跟踪。移出跟踪影响所有克隆与分支，并要同时评估供应商是否需重发组件，需用户决定后再动。
3. **S3**：`ApiClient._clientQuery` 仍把 `userToken` 放进 `/Client/` 的 URL 查询；令牌仍存 `SharedPreferences`。前者要先与后端确认只认鉴权头（跨端契约），后者要迁 Keychain / Keystore。
4. release 包的 Manifest / Info.plist 与抓包核对（S1 目前只在源码层面确认）。
5. 会话隔离、原生回调截止时间、事件解析、纪念日缓存隔离、图片内存、启动与刷新性能——`RELEASE_READINESS_REVIEW.md` 的后续批次。
6. 一小时掉登录的后端侧根因，见 `docs/history/2026-09/2026-09-09-backend-session-expiry.md`。

## 环境边界

- ssh 开发机：没有 Flutter/Dart SDK、Android SDK、Xcode——静态检查和文档可以做，analyze / test / 编译一律做不了。
- iOS 需 macOS/Xcode；配网与 OTA 需真实设备，本机测试不能替代。

## 续接步骤

先读本文件与项目规则，检查用户是否已手动提交本轮工作；存在未提交修改时不要覆盖、stash 或自动 pull。Git 是跨环境唯一共享来源。
