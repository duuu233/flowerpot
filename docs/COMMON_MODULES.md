# 公共模块复用说明

本项目已对照 `D:\Work\learn\flutter`，复用与具体产品 UI、相框 BLE 业务无关的公共能力。

## 已复用

- `lib/src/core/network/`：统一 JSON/文件上传请求、连接复用、公共参数、会话持久化、异常映射、网络重试、鉴权失效和日志脱敏。
- `lib/src/core/backend/`：封装 APP 后端的国内账号、用户设备、植物目录/绑定和设备图片接口；页面不直接访问 HTTP。
- `lib/src/shared/widgets/app_toast.dart`：全局单实例、居中展示、自动消失、读屏播报的 Toast。
- `lib/src/features/auth/domain/auth_validator.dart`：手机号、邮箱、验证码和密码的统一校验。
- `lib/src/features/auth/presentation/verification_code_countdown.dart`：验证码发送后的 60 秒防重复请求。
- `lib/src/core/cache/image_cache_cleanup.dart`：退出登录和注销后清理上一账号的内存图片缓存。
- `assets/images/`：应用图片资源目录，已在 `pubspec.yaml` 注册。

## 保留项目实现

- 页面、主题、Design Token 和动效继续使用 YSplanter 设计，不复制兄弟项目 UI。
- 国内登录注册先由 `AppBackendRepository` 建立 APP Token，再用返回的 `userNo` / `tuYaPwd` 通过 `TuyaRepository` 建立设备会话；失败时清理 APP Token，避免双会话不一致。海外邮箱和未配置 REST 的开发模式保留原链路。
- 相框 BLE、投屏、图库和 OTA 等产品专属模块不迁移。

REST 服务接入时通过 `--dart-define=API_BASE_URL=https://...` 提供服务源站（不含 `/swagger-ui.html#/`），由 `FlowerpotApp` 创建 `HttpAppBackendRepository`。当前未配置时会回落到 `ApiConfig` 中的临时 HTTP 地址；显式传 `API_BASE_URL=none` 才使用 `DisabledAppBackendRepository`。仅注入 Mock 涂鸦仓库不会禁用 REST，测试还应显式注入禁用型或 Fake 后端。业务页面只通过 `FlowerpotState` 使用这些能力。明文回落、令牌存储、写请求重试及会话隔离的待整改项见 [`RELEASE_READINESS_REVIEW.md`](RELEASE_READINESS_REVIEW.md)。
