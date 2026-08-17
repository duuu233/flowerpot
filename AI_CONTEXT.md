# AI 项目上下文

> 文档类型：当前项目上下文
> 状态：Active
> 最后核验：2026-08-17
> 适用范围：`flowerpot` 当前工作树
> 事实来源：源码与 CodeGraph、`pubspec.yaml`、平台配置和 `docs/` 中的当前文档

## 1. 项目定位

`flowerpot` 是 YSplanter 智能花盆的 Flutter iOS/Android 客户端，覆盖账号、设备配网、设备与植物状态、报表、设备设置、固件升级、动画资源和个人中心。PC 管理后台与服务端是独立项目，不应把管理端页面或部署规则写进本仓库。

项目可在没有涂鸦密钥和安全组件时以 Mock/静态预览方式运行；真实设备能力通过原生 Smart Life App SDK 与 Flutter `MethodChannel` 桥接。

Git 是办公室电脑、家庭电脑和远程 SSH 环境之间唯一共享的事实来源。本机 SDK、构建缓存、签名材料、`.codegraph/` 和未提交工作区不属于跨机器共享状态。

## 2. 技术栈与常用命令

- Flutter / Dart，Dart SDK 约束为 `^3.11.5`。
- Material 3、feature-first 页面组织、命名路由。
- `ChangeNotifier` 的 `FlowerpotState` 管理应用状态，`FlowerpotScope` 通过 `InheritedNotifier` 向页面提供状态。
- `http` 提供 REST 客户端，`shared_preferences` 保存会话和本地偏好，`image_picker` 选择图片。
- Android Kotlin、iOS Swift 负责涂鸦 SDK 原生桥接。

```bash
flutter pub get
dart format lib test
dart analyze lib test
flutter test
flutter run
```

真实 SDK 模式按平台配置完成后使用：

```bash
flutter run --dart-define=TUYA_ENABLED=true
```

`TUYA_ENABLED=true` 会选择真实 Repository；`StaticPreviewConfig.enabled` 只控制 Mock 后端是否预置演示设备，不需要为真实模式修改。真实设备流程仍必须准备好平台密钥、安全组件和签名。若接入独立 REST 服务，通过 `--dart-define=API_BASE_URL=https://...` 注入地址。各环境应使用 PATH 中的 Flutter/Dart；README 中的绝对路径只可视为单机示例。

## 3. 架构与数据流

```text
lib/main.dart
  → FlowerpotApp
  → FlowerpotState.initialize()
  → FlowerpotScope / AnimatedBuilder
  → AppRoutes.onGenerateRoute()
  → features/*/presentation
```

设备与账号链：

```text
页面
  → FlowerpotScope.of(context)
  → FlowerpotState
  → TuyaRepository
      ├─ TUYA_ENABLED=false：MockTuyaRepository
      └─ TUYA_ENABLED=true：MethodChannelTuyaRepository
                              → Android/iOS Smart Life SDK
```

`ActionResult` 同时带回 `message` 与 `code`：产品页面只展示 `message`，SDK 联调页用 `code` 区分平台配置错误（`sdk_unavailable`、`credentials_missing`、`security_component_mismatch`）与账号错误。

REST 公共能力位于 `lib/src/core/network/`：`ApiClient` 从 `API_BASE_URL` 读取服务地址，`ApiSession` 用 `SharedPreferences` 持久化 `userToken` 并统一处理鉴权失效。当前账号和设备主链仍以 `TuyaRepository` 为边界，业务页面不应直接发 HTTP 请求。

## 4. 关键目录

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart` | Flutter 入口与系统 UI 初始化。 |
| `lib/src/app/` | 根应用、主题和 `FlowerpotScope`。 |
| `lib/src/state.dart` | 当前集中式应用状态与业务编排。 |
| `lib/src/routes/` | 命名路由、鉴权分流和页面参数。 |
| `lib/src/features/` | auth、home、devices、profile、preview 等业务页面，以及 devtools 下不属于产品动线的 SDK 联调页。 |
| `lib/src/design_system/` | Design Token、资源索引和公共视觉组件。 |
| `lib/src/shared/` | 跨 Feature 复用组件。 |
| `lib/src/core/network/` | REST 请求、会话、异常和重试。 |
| `lib/src/tuya/` | 涂鸦配置、模型、Mock 与 MethodChannel Repository。 |
| `android/`、`ios/` | 平台工程、SDK 配置和桥接实现。 |
| `test/` | 网络、配置、页面和公共组件测试。 |
| `docs/` | 架构、UI、平台接入和冻结历史记录。 |

## 5. 当前核心模块

- 账号：国内手机号、海外邮箱、验证码/密码、注册、找回密码、退出和注销。
- 首页与设备：底部菜单（首页/我的）、设备列表即首页、配网（搜索 → 选择 → Wi-Fi → 成功）、选择植物、状态详情、报表和设备信息。
- 设备控制：显示、听觉、触觉、振动、行为时段、温标、时钟、校准与系统修复。
- 内容与维护：动画资源、设备分享、解绑、恢复出厂和 OTA。
- 个人中心：资料、账号安全、帮助、协议、隐私、关于与偏好。
- 设计系统：统一色彩、间距、资源、页面骨架和公共 Widget。
- 联调工具：登录页「涂鸦 SDK 联调」与「我的」页标题栏图标都指向 `/devtools/tuya`，直接调用注册、登录、会话与设备列表并显示原始失败码，配网联调前先在该页确认平台配置；debug/profile 常开，release 需 `--dart-define=TUYA_DEBUG_TOOLS=true`。

功能完成度以 [`docs/PRD_IMPLEMENTATION.md`](docs/PRD_IMPLEMENTATION.md) 为跟踪入口，UI 实施要求以 [`docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`](docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md) 为准。

## 6. 重要设计约束

1. 页面通过 `FlowerpotState` 和 Repository 使用业务能力，不直接依赖 MethodChannel 或散落 HTTP 调用。
2. `TuyaConfig.dp` 是 UI 读写与产品 PID 功能点之间的契约；变更必须与固件、涂鸦平台和测试一起核对。
3. `TUYA_ENABLED` 只是选择真实 Repository 的编译期开关；平台安全组件、AppKey/AppSecret、包名和签名仍必须匹配，且运行环境必须真正按 `arm64-v8a` 或 `armeabi-v7a` 启动应用（涂鸦原生库不提供 x86/x86_64）。部分 x86_64 模拟器即使 ABI 列表包含 ARM，通用 APK 仍会优先以 x86_64 运行；显式 arm64 构建与安装方法见 `docs/TUYA_SDK_SETUP.md`。Mock 业务模式不依赖涂鸦调用；本机已有安全 AAR 时 Application 仍会尽力初始化 SDK，但失败不阻止 Mock UI。
4. 当前 `StaticPreviewConfig.enabled` 为 `true`，只表示 Mock 后端不预置演示设备；启动入口、鉴权分流和页面导航与正式流程一致（登录页 → `AppShell`）。真机链路仍需单独验证会话恢复和真实设备流程。
5. 新 UI 优先复用 `design_system` 和 `shared` 组件，遵循项目自己的 YSplanter 视觉规范，不复制参考项目的产品 UI。
6. 命名路由与参数类型集中在 `AppRoutes`；修改路由前用 CodeGraph 检查页面和测试调用方。
7. CodeGraph 描述当前源码结构；Markdown 负责产品契约、平台配置、操作方法、设计决策和历史。

## 7. 环境与秘密管理

- `TUYA_ENABLED`、`API_BASE_URL`、`TUYA_DEBUG_TOOLS` 通过 `--dart-define` 注入。
- Android 涂鸦密钥放在未提交的 `android/local.properties`；安全组件按接入文档放置，不得写入普通 Markdown。
- iOS 安全组件、Bundle ID、Universal Link/App Link 和签名资料按平台受控管理。
- 文档、源码、历史记录和提交信息不得包含 Token、AppSecret、密码、签名材料、真实 Wi-Fi 凭据或用户数据。

## 8. 开发与维护流程

开始任务时按以下顺序读取：

1. `AGENTS.md`
2. 本文件
3. `docs/README.md`
4. 与任务相关的 Active 文档
5. CodeGraph 中的源码符号、调用链和影响范围
6. 仅在追查原因时读取相关 Historical 记录

执行约定：

1. 先运行 `git status --short`，保护正在进行的 UI、平台或资源改动。
2. `.codegraph/` 存在时，结构分析先运行 `codegraph status .` 和 `codegraph explore 问题或符号`。
3. 拉取代码后运行 `codegraph sync .`；完成有意义的源码修改后再次同步并检查状态。
4. Dart 代码至少运行格式化、`flutter analyze` 和相关测试；平台改动再执行相应 Android/iOS 构建或明确写出未验证项。
5. 架构、DP、平台配置、命令或产品行为变化时更新负责该事实的 Active 文档。
6. 一次集中修改建立一份 `docs/history/YYYY-MM/YYYY-MM-DD-主题.md`，不在 AI_CONTEXT 追加流水账。

## 9. 已知风险与未确认项

- Android Home SDK 7.5.1 与 Expansion SDK 7.8.0 已在本机 arm64 强制安装模式下完成初始化验证；账号、家庭、配网、设备控制和真机链路仍未完成联调，Mock 或 SDK 初始化通过不等于真实业务链通过。
- 静态演示构建使用 Mock 后端与空设备列表，接口错误、超时和真实鉴权行为都不会在其中出现。
- `FlowerpotState` 被大量页面调用，继续膨胀会扩大变更影响面；拆分前必须先分析调用链并保留行为。
- DP 101–123 的最终映射、倍率、枚举、统计服务、动画传输、分享和 OTA 回调仍需平台/固件确认。
- Android/iOS 包名与桥接正在工作区中演进；不要根据旧历史文档恢复已删除的平台文件。
- 当前工作区有大量未提交的 UI、资源、路由、平台与测试改动，任何任务都必须先识别所有权并避免覆盖。

## 10. 文档地图

- [`docs/README.md`](docs/README.md)：文档导航、状态和维护规则。
- [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md)：当前项目目录和分层。
- [`docs/COMMON_MODULES.md`](docs/COMMON_MODULES.md)：从参考项目复用的公共能力和保留边界。
- [`docs/PRD_IMPLEMENTATION.md`](docs/PRD_IMPLEMENTATION.md)：PRD 实现与待联调清单。
- [`docs/TUYA_SDK_SETUP.md`](docs/TUYA_SDK_SETUP.md)：涂鸦平台与原生 SDK 接入。
- [`docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`](docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md)：UI 页面实施规范。
- [`docs/history/README.md`](docs/history/README.md)：本地操作更新记录规范与模板。

## 11. 兄弟项目边界与同步触发

| 项目 | 主要职责 | 需要同步的变化 |
| --- | --- | --- |
| `flowerpot` | YSplanter Flutter 用户端 | 用户态接口模型、设备状态、DP、配网、OTA、协议和客户端口径。 |
| `flowerpot-web` | 花盆产品 PC 管理后台 | 产品、版本、用户设备、管理菜单、权限和运营字段。 |
| `web-ui-v2` | BoltFox PC 管理后台 | 仅在复用的管理端契约或公共前端方案变化时同步。 |

跨项目同步必须在各自历史记录中写明上游来源、新契约、已同步内容、有意差异和未完成项。不要把 Flutter 命令、涂鸦 SDK、DP 或移动签名规则复制到 Web 项目。

## 12. AI 工作备注

- 源码、CodeGraph 和当前工作树优先于旧截图、旧会话记录或绝对路径说明。
- 不覆盖与当前任务无关的未提交文件，不恢复用户已经删除或迁移的内容。
- 不把某台机器的 SDK 安装状态、缓存或签名能力写成跨环境事实。
- Historical 只用于追溯；与源码或 Active 文档冲突时，先核验当前实现并修正文档。
