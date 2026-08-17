# 登录页涂鸦 SDK 联调入口

> 文档类型：Historical Change Record
> 日期：2026-08-17
> 环境：远程 SSH 工作树（本机无 Flutter/Dart SDK）
> 分支与起始版本：main / 42f6ee1
> 范围：登录页入口、`features/devtools`、`FlowerpotState` 自检能力、`ActionResult` 契约
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

Android 侧只验证到 `ThingHomeSdk` 与 `ThingOptimusSdk` 初始化成功，账号、家庭、配网等真实业务链仍未联调。产品登录页要求勾选协议、只提供国内手机号入口，并且把失败码折叠成一句文案，不适合逐步定位平台配置问题。本次目标是给登录页增加一个直接调用注册与登录的联调入口，让真机可以继续往配网方向推进。

## 变更内容

- 新增 `lib/src/features/devtools/presentation/tuya_debug_page.dart`：运行环境、账号参数、注册、登录、会话与设备、调用日志六段；账号类型在手机号（国家码 86）与邮箱（国家码 1）之间切换，注册验证码用 type 1、登录验证码用 type 2，与桥接的手机／邮箱接口分发一致。
- 新增 `lib/src/features/devtools/debug_tools_config.dart`：debug 与 profile 构建常开，release 需要 `--dart-define=TUYA_DEBUG_TOOLS=true`。
- `AppRoutes` 增加 `tuyaDebug`（`/devtools/tuya`）并加入公开路由集合，未开启联调工具时该路由回落到登录页。
- 登录页底部把「体验模式」与新的「涂鸦 SDK 联调」放进 `Wrap`，窄屏自动换行；联调回调在未开启时为 `null`，入口随之隐藏。
- 「我的」页标题栏增加同一入口的图标按钮：已登录的冷启动直接进入 `AppShell`，否则联调页只能通过退出登录才能到达。该按钮只加在 AppBar 的 `actions`，不改动 Figma 菜单面板。
- `ActionResult` 增加可选 `code`，`FlowerpotState._guard` 把 `TuyaException.code`、校验失败与未预期异常分别标记为原始码、`invalid_input` 和 `unexpected_error`。
- `FlowerpotState` 增加 `probeSdk`、`probeSession`、`probeDevices` 与 `usingMockBackend`：分别重跑初始化、按 SDK 会话对齐本地状态、以不吞错的方式刷新设备列表，以及判断当前是否由 Mock 后端应答。
- 新增 `test/features/devtools/tuya_debug_page_test.dart`，并在 `auth_page_test` 与 `widget_test` 中补充入口存在与路由跳转用例。
- 更新 `docs/TUYA_SDK_SETUP.md`（新增 5.3）、`AI_CONTEXT.md`、`PROJECT_STRUCTURE.md` 与文档索引。

## 关键决策

- 联调页仍然只经过 `FlowerpotState` 与 `TuyaRepository`，不直接使用 `MethodChannel`，因此不破坏现有架构边界；它与产品页面的差别只是绕开协议勾选并展示 `code`。
- 失败码通过 `ActionResult.code` 回传，而不是给状态层加一套调试专用返回类型；现有页面继续只用 `message`，调用点无需修改。
- 入口默认对 release 关闭。真实链路验证常常需要 release 签名 APK，所以保留 `TUYA_DEBUG_TOOLS` 显式开关，而不是硬编码 `kDebugMode`。
- 页面与日志只显示脱敏账号（手机号保留前 3 后 2，邮箱保留首字符与域名），不显示密码、验证码和密钥，避免复制日志时带出凭据。
- 「拉取设备列表」独立成一个动作：它会触发家庭查询与自动建家，是配网前最容易失败又最容易被登录成功掩盖的一步。
- `AppPrimaryButton` 的 `Row` 不会换行，主题字号 18 且字距 2；在 375dp 下按钮内可用宽度只有约 263px，360dp 只有约 248px。因此联调页的主按钮文案压到「进入 App 配网」并去掉图标，而不是改动被多个页面复用的 `AppPrimaryButton`。
- `tuyaDebug` 只在联调工具开启时进入公开路由集合，关闭时该路径不再被视为公开页。
- `probeSession` 在没有会话时保留 `_demoMode`：查询会话不等于退出体验模式，`enterDemo` 换上的仓库仍然在位。

## 外部操作

无。未修改涂鸦平台配置，未接触本机密钥、安全组件与签名材料。

## 验证结果

- 本环境没有安装 Flutter/Dart，`dart format`、`dart analyze` 与 `flutter test` 均未执行；改动只做了人工核对与一次独立的逐符号静态复查（组件构造参数、`design_system` 导出、`FlowerpotState` 成员、路由分支、测试 Key 与断言、常量与空安全）。
- 复查发现主按钮文案会在 375dp 与 360dp 下触发 `RenderFlex` 溢出并使两个 `widget_test` 的 `takeException` 断言失败，已按上面的决策修正；同时收紧了公开路由集合与 `probeSession` 的 `_demoMode` 处理。
- 静态复查不等于编译与测试通过：本次没有任何运行时结论，格式化、分析、测试与真机联调必须在带 SDK 的开发机上完成。

## 未完成项与风险

- 待在带 SDK 的机器上执行 `dart format lib test`、`flutter analyze` 与 `flutter test`，其中联调页与三个入口用例是新增的，可能需要按实际布局微调断言。联调页测试固定在 480x1400 表面，缩小该尺寸前要先确认按钮文案宽度。
- 联调页本身未在真机运行过：注册、登录、会话、家庭与设备列表的真实返回仍未验证。
- 页面按 `LoginRegion` 绑定国家码（手机号 86、邮箱 1）。若测试账号需要其他国家码或邮箱走 86 数据中心，需要扩展 `TuyaRepository` 的账号参数契约。
- 设备 DP 实时上报仍未接通，联调页也只能读到 `getDevices` 时的一次性快照。

## 回滚或恢复

删除 `lib/src/features/devtools/`、`test/features/devtools/`，回退 `AppRoutes`、`auth_page.dart`、`state.dart`、`tuya_models.dart` 与两个测试文件的本次改动即可恢复；`ActionResult.code` 是可选参数，回退不影响其他调用点。
