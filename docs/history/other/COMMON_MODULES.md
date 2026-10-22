# 公共模块复用说明

本项目已对照 `D:\Work\learn\flutter`，复用与具体产品 UI、相框 BLE 业务无关的公共能力。

## 已复用

- `lib/src/core/network/`：统一 JSON/文件上传请求、连接复用、公共参数、会话持久化、异常映射、网络重试、鉴权失效和日志脱敏。
- `lib/src/core/backend/`：封装 APP 后端的国内账号、用户设备、植物目录/绑定和设备图片接口；页面不直接访问 HTTP。
- `lib/src/shared/widgets/app_toast.dart`：全局单实例、居中展示、自动消失、读屏播报的 Toast。花盆及割草机复用 `showAppMessage` 映射 success / error / info；相同离线失败使用「设备已离线」与 error 语义，不另做一套组件。设备列表在线 / 离线胶囊共用；割草机可进入页面连接蓝牙的例外见 `PRODUCT_RULES.md` §4.10。
- `lib/src/features/auth/domain/auth_validator.dart`：手机号、邮箱、验证码和密码的统一校验。
- `lib/src/features/auth/presentation/verification_code_countdown.dart`：验证码发送后的 60 秒防重复请求。
- `lib/src/core/cache/image_cache_cleanup.dart`：退出登录和注销后清理上一账号的内存图片缓存。
- `assets/images/`：应用图片资源目录，已在 `pubspec.yaml` 注册。

## 保留项目实现

- 页面、主题、Design Token 和动效继续使用 YSplanter 设计，不复制兄弟项目 UI。
- 国内登录注册先由 `AppBackendRepository` 建立 APP Token，再用返回的 `userNo` / `tuYaPwd` 通过 `TuyaRepository` 建立设备会话；失败时清理 APP Token，避免双会话不一致。海外邮箱和未配置 REST 的开发模式保留原链路。
- 相框 BLE、投屏、图库和 OTA 等产品专属模块不迁移。

REST 服务接入时通过 `--dart-define=API_BASE_URL=https://...` 提供服务源站（不含 `/swagger-ui.html#/`），由 `FlowerpotApp` 创建 `HttpAppBackendRepository`。当前默认正式 HTTPS 源站为 `https://api.yikaltd.com`，配置校验只接受 HTTPS 源站；`none` 不属于合法地址。隔离测试需要显式注入 `DisabledAppBackendRepository` 或 Fake 后端。仅注入 Mock 涂鸦仓库不会禁用 REST，测试还应显式注入禁用型或 Fake 后端。业务页面只通过 `FlowerpotState` 使用这些能力。网络、令牌存储、写请求重试及会话隔离的发布核查见 [`RELEASE_READINESS_REVIEW.md`](RELEASE_READINESS_REVIEW.md)。


## APP 后端会话失效协议

按 `PRODUCT_RULES.md` §4.3.1，`ApiClient` 仅在响应业务字段 `retCode=406` 时清除 `ApiSession` 并通知失效回调。
HTTP 401/406 及其它业务错误仍抛出原错误，不清除内存或持久化 Token。
`ApiException.isAuthError` 仅允许业务 406；`authError: false` 用于把 HTTP 406 等传输错误排除，其它错误不能强制提升为会话失效。
`FlowerpotState` 的统一异常处理使用同一分类，406 只清 APP 后端会话，保留涂鸦与设备列表；请求代次保护继续隔离旧会话的迟到响应。

## 启动确认弹窗

割草机安全提醒与时间设置复用 `showAppDialog`。长确认文案通过可选 `stackActions` 纵向显示全宽按钮；其余调用默认保持原有横排。时长选择限定当日18点前可用整小时，不缓存用户确认。DP115拒绝通知复用同一个公共单按钮提示框，标题「设备异常」、按钮「我已处理」；等待安全/时间交互结束再弹，不创建新的弹窗组件。

## 连续弹框切换

固件提醒复用 `showAppDialog` 的可选 `waitForDismissal: true`，等待对话框退出动画和 overlay 移除再继续。其余调用默认仍在关闭结果返回时继续。强制提醒和版本确认采用相同退场完成等待；升级状态、进度阶段与终态规则见 [OTA_实现说明.md](OTA_实现说明.md)。

`FlowerpotState.canStartFirmwareUpgrade(deviceId)` 供主动提醒与手动确认后的发起入口共用：花盆保持原规则，割草机按目标设备最新原始 DP117 仅允许 charging（1），不借用页面单例或花盆同号字段；已运行升级的进度入口在检查前处理。
