# AI 项目上下文

> 文档类型：当前项目上下文
> 状态：Active
> 最后核验：2026-09-05
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
- `http` 提供 REST 客户端，`crypto` 负责后端密码接口要求的 MD5，`shared_preferences` 保存会话和本地偏好，`image_picker` 选择图片。
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

`TUYA_ENABLED=true` 会选择真实 Repository；`StaticPreviewConfig.enabled` 只控制 Mock 后端是否预置演示设备，不需要为真实模式修改。真实设备流程仍必须准备好平台密钥、安全组件和签名。通过 `--dart-define=API_BASE_URL=https://...` 注入 REST 地址；当前未配置时仍回落临时 HTTP，只有显式 `API_BASE_URL=none` 才禁用后端，这是发布前待修复项。各环境应使用 PATH 中的 Flutter/Dart；README 中的绝对路径只可视为单机示例。

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
      ├─ AppBackendRepository（显式地址或当前临时回落；none 禁用）
      │   → ApiClient / ApiSession
      │   → 国内短信、登录/注册、用户设备、植物、设备图片
      └─ TuyaRepository
          ├─ TUYA_ENABLED=false：MockTuyaRepository
          └─ TUYA_ENABLED=true：MethodChannelTuyaRepository
                                  → Android/iOS Smart Life SDK
```

国内账号在 APP 后端登录/注册成功后，由后端返回 `userNo` 与 `tuYaPwd`，`FlowerpotState` 再用这组映射凭据建立涂鸦会话；任一步失败都会清理 APP Token，避免半登录状态。手机验证码登录是登录注册一体的：`userLoginVerifyCode` 以 `retCode` 403 + 「不存在/未注册」文案回绝时，`HttpAppBackendRepository` 用同一条验证码调 `userRegisterMobile` 补注册（密码随机生成占位），注册接口返回的会话字段与登录接口一致，因此不再登录第二次。海外邮箱和未配置 `API_BASE_URL` 的开发模式保留原涂鸦账号链。

设备主动上报是反方向的一条单向链，不经过方法通道：

```text
Android IDevListener / iOS ThingSmartDeviceDelegate
  → EventChannel com.common.yikaltd/tuya_events
  → MethodChannelTuyaRepository（并入最近一次设备快照）
  → TuyaRepository.deviceUpdates
  → FlowerpotState → notifyListeners()
```

`ActionResult` 同时带回 `message` 与 `code`：产品页面只展示 `message`，SDK 联调页用 `code` 区分平台配置错误（`sdk_unavailable`、`credentials_missing`、`security_component_mismatch`）与账号错误。

REST 公共能力位于 `lib/src/core/network/`，业务契约位于 `lib/src/core/backend/`：`ApiClient` 从 `API_BASE_URL` 读取服务地址，`ApiSession` 用 `SharedPreferences` 持久化 `userToken` 并统一处理鉴权失效，`HttpAppBackendRepository` 封装账号、用户设备、植物与图片接口。业务页面不直接发 HTTP 请求，由 `FlowerpotState` 编排 APP 后端与涂鸦设备会话。

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
| `lib/src/core/backend/` | APP 后端账号、用户设备、植物、设备图片模型与接口封装。 |
| `lib/src/tuya/` | 涂鸦 DP 表与配置、模型、raw 历史解码、Mock 与 MethodChannel Repository。 |
| `android/`、`ios/` | 平台工程、SDK 配置和桥接实现。 |
| `test/` | 网络、配置、页面和公共组件测试。 |
| `docs/` | 架构、UI、平台接入和冻结历史记录。 |

## 5. 当前核心模块

- 账号：配置 `API_BASE_URL` 后，国内手机号短信、验证码/密码登录与注册走 APP 后端，再用返回的映射凭据登录涂鸦；验证码登录未注册即自动建号；海外邮箱及找回密码等原有能力保留涂鸦链路。
- 设备实时性：DP 上报、上下线和解绑由原生监听推给 Dart，页面自动刷新；温标（146）与时间格式（147）下发后 App 自身展示跟随。
- 状态文案：需水（107）、光照（108）、空气温度（113）、空气湿度（115）四条枚举的文案集中在 `lib/src/tuya/tuya_status_copy.dart`，状态页顶部与首页状态卡片同源，设备没上报时按同一套阈值兜底（113 的兜底舒适区间 18–28℃ 也放在这里，温度状态页与首页共用）。2026-09-08 起每条状态都备了中英两份，取用走 `waterNeedsCopy` 这类按 `FlowerpotState.languageCode` 查表的方法，非英文一律回落简体中文；首页「今日养护」卡片改为轮播这四条状态的建议（5 秒一条，`HomeCareBanner`），文案与卡片、状态页同源。**注意：App 至今没有引入 `flutter_localizations`/arb，其余界面文案仍是硬编码中文**，这张表只覆盖这批状态文案。
- 多语言：`lib/src/shared/l10n/` 是界面文案框架——`AppLanguage` 枚举（现有 zh / en，加语种就加枚举值，缺译文按 `fallbacks` 回落到简中）、`AppLocalizationsScope`（挂在 `MaterialApp.builder`，切语言整树重译）、`AppL10n` 文案目录（`t({语言: 文案})`）。设置页的语言列表由枚举生成。**只有 2026-09-08 改动涉及的页面接入了目录，其余页面仍是硬编码中文**；`flutter_localizations` 尚未引入，Material 内建文案恒为英文。做法对齐相册 APP，区别是文案用 Map 而不是位置参数。
- 首页与设备：无底部菜单，设备列表即首页、左上角头像进入「我的」（顶栏正中显示当前设备名称，未绑定设备时是品牌标识）、配网（搜索 → 选择 → Wi-Fi → 成功）、选择植物、状态详情、报表和设备信息。设备详情页入口有三道门禁：离线的花盆拦在列表页并提示「请打开设备并保持在线」；DP 116 为空直接进添加植物流程；进页后 DP 162 报 1（异常）弹「植物确认」，确认/忽略各自再过一次二次确认才下发 2/3，之后按设备重新上报的 116 刷新植物内容。设备设置页有「自动检测植物」纯开关（DP 163，平台尚未导出），关掉后不再弹确认。后端设备行按涂鸦 `deviceId` 关联；植物目录、详情、绑定/删除与设备图片使用 APP 后端。**分工要点**：涂鸦只回答「这盆里是哪一株」——设备通过 DP 116 `plant_variety` 上报后台配好的标识符（`tuYaRemark` 字符串，不是数字 ID），App 选植物时也是把标识符写回 116（分类另写 161）；植物的内容本身全部来自 APP 后端 `Client/Product/getProductPlantList` 的目录行——`plantImg`（列表与详情的图片）、别名、简介、最适温湿度、光照 / 浇水 / 温湿度建议、养护难度、`categoryType`，由 `_plantForIdentifier` / `ensurePlantProfile` 按 116 的标识符匹配，匹配不上就补拉一次目录再解析，仍失败则回落本地目录且不打断详情页；详情页上的实时数值（光照 107、需水 108、温度 113、湿度 115 等）来自设备 DP 上报，与这条后端链路无关。 2026-09-09 起**已绑定设备首页正中那张图也走这条链路**：`HomeDashboardModel.plantImageUrl` 取 `device.plant.imageUrl`，`HomePlantOverview` 优先画后台配的图，字段为空或图片加载失败才回落本地 `AppAssets.smartPlanterWithPlant`；植物详情页 `_PlantDetailArtwork` 早就是同一口径，回落的是 `AppAssets.plantImage(plant.id)`（未知 id 再退到通用图标）。设备只支持 2.4GHz Wi-Fi 配网、没有蓝牙配网；配网三页全部走真实桥接调用——搜索与选择页用 `scanWifi` 找设备在 AP 模式下拉起的热点，Wi-Fi 页带入真实 2.4G 网络列表，「开始配网」一次点击由 `FlowerpotState.pairViaHotspot` 串完取令牌 → App 连设备热点 → 配网；平台不能由 App 连热点（iOS、Android 9 及以下）时回落到手动引导；任何一步失败、用户退出页面或等待超时都会释放热点连接与进程网络绑定（`leaveDeviceHotspot` / `cancelPairing`），详见 `docs/TUYA_SDK_SETUP.md` 5.3 与 6.3。
- 设备控制：显示、LED、听觉、触觉、振动、行为时段、温标、时钟、校准与系统修复。LED 设置页是单开关，与显示页共用 `disp_brightness_switch`（117）——2026-09-03 的功能点表没有独立的 LED 开关。
- 我的与关于：「我的」进页即 `refreshUserInfo()` + `loadBasicData()`（昵称此前只有个人信息页会刷、意见反馈邮箱此前写死）；意见反馈读后台平台邮箱并复制到剪贴板；关于页去掉「版本说明」，「检查更新」与 App 启动检测共用一套升级弹窗——`compulsory==1` 强制升级不可取消，其余有新版本时在「关于YSplanter」点红点。`getLastVersion` 按 swagger 的 `AppVersionConApiOutput` 解析（`isUpdate`/`compulsory`/`downloadPath`/`upgradeTips`）。**版本号仍是 `AboutPageModel.current()` 里写死的 1.0.0，没有 package_info；「立即更新」只复制下载链接，没有 url_launcher。**
- 状态详情的养护建议 2026-09-08 起写在 `TuyaStatusCopy` 的第三段 `advice` 里（中英各 12 条），四个状态页按界面语言取，不再各写一段。
- 设置与行为：「自动检测植物」（DP 163）和 LED 设置一样是独立页面里的单开关，设置页那一行只显示状态；帮助中心 2026-09-08 从「我的」搬到设备设置页；设备设置右上角的分享入口按产品要求先隐藏（`_shareEntryEnabled`）；「行为」页除午休 / 夜间两个时段外，第三张卡就是「休眠模式」本身（2026-09-09 由二级页面改为页内展开，`StandbySettingsCard`，原 `standby_settings_page.dart` 与 `AppRoutes.standbySettings` 已删除）——版式与交互跟午休 / 夜间一致：开关 DP 151 即时下发，「延迟时间」一行点开滚轮弹窗（`showStandbyDelayDialog`），按弹窗里的「保存」才写 DP 152（1–180 分钟），取值没变就不发。「其他设置」已删除只弹「暂未开放」的「系统文件更新」「修复系统文件」两行。
- 内容与维护：定制动画（图库多选、上传、删除、置顶，分别对应 155/156/157）、纪念日（固定生日/结婚走 158/159，自定义条目走 154 的 upsert 帧，列表满员 12 条 = 10 自定义 + 2 固定）、设备分享、解绑、恢复出厂和 OTA。OTA 没有对应功能点，走 SDK 的 OTA 接口：`checkFirmware` 查版本、`startFirmwareUpgrade` 只发起，进度与成败从事件通道回来，版本号只在 success 时更新。App 不直接和设备说话——进「设置」和「其他设置」页时静默查一次版本，查到新版本就在这两页各点一个小红点，用户点一下才通知涂鸦给设备下发升级。
- 个人中心：资料、账号安全、帮助、协议、隐私、关于与偏好。
- 设计系统：统一色彩、间距、资源、页面骨架和公共 Widget。所有提示/确认弹窗走 `AppDialog`（`design_system/widgets/dialogs/app_dialog.dart`），版式取自兄弟项目 `flutter` 的同名组件、配色换成 YSplanter 的品牌青；页面里不再出现 Material `AlertDialog`。
- 联调工具：登录页「涂鸦 SDK 联调」与「我的」页标题栏图标都指向 `/devtools/tuya`，直接调用注册、登录、会话与设备列表并显示原始失败码，配网联调前先在该页确认平台配置；debug/profile 常开，release 需 `--dart-define=TUYA_DEBUG_TOOLS=true`。

功能完成度以 [`docs/PRD_IMPLEMENTATION.md`](docs/PRD_IMPLEMENTATION.md) 为跟踪入口，UI 实施要求以 [`docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md`](docs/UI/FLUTTER_UI_IMPLEMENTATION_STANDARD.md) 为准。

## 6. 重要设计约束

1. 页面通过 `FlowerpotState` 和 Repository 使用业务能力，不直接依赖 MethodChannel 或散落 HTTP 调用。
2. `TuyaConfig.dp` 是 UI 读写与产品 PID 功能点之间的契约；变更必须与固件、涂鸦平台和测试一起核对。当前表来自 `assets/智能花盆test(yciq4kssu1fv8umn)_09_03.xlsx`，PID `yciq4kssu1fv8umn`，覆盖 101–160。
3. `TUYA_ENABLED` 只是选择真实 Repository 的编译期开关；平台安全组件、AppKey/AppSecret、包名和签名仍必须匹配，且运行环境必须真正按 `arm64-v8a` 或 `armeabi-v7a` 启动应用（涂鸦原生库不提供 x86/x86_64）。部分 x86_64 模拟器即使 ABI 列表包含 ARM，通用 APK 仍会优先以 x86_64 运行；显式 arm64 构建与安装方法见 `docs/TUYA_SDK_SETUP.md`。Mock 业务模式不依赖涂鸦调用；本机已有安全 AAR 时 Application 仍会尽力初始化 SDK，但失败不阻止 Mock UI。
4. 当前 `StaticPreviewConfig.enabled` 为 `true`，只表示 Mock 后端不预置演示设备；启动入口、鉴权分流和页面导航与正式流程一致（登录页 → `AppShell`）。真机链路仍需单独验证会话恢复和真实设备流程。
5. 新 UI 优先复用 `design_system` 和 `shared` 组件，遵循项目自己的 YSplanter 视觉规范，不复制参考项目的产品 UI。界面不标注占位数据，真假以源码和 SDK 联调页的调用日志为准。
6. 命名路由与参数类型集中在 `AppRoutes`；修改路由前用 CodeGraph 检查页面和测试调用方。
7. CodeGraph 描述当前源码结构；Markdown 负责产品契约、平台配置、操作方法、设计决策和历史。

## 7. 环境与秘密管理

- `TUYA_ENABLED`、`API_BASE_URL`、`TUYA_DEBUG_TOOLS` 通过 `--dart-define` 注入。
- `API_BASE_URL` 必须是服务源站（例如 `https://api.example.com`），不能填写 `/swagger-ui.html#/` 页面地址；当前空值回落临时 HTTP，显式 `none` 才使用禁用型 Repository。Mock 测试应同时注入 Fake/禁用型后端。
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
- 除已确认的 DP 116 外，DP 101–115、117–123 的最终映射、倍率、枚举、统计服务、动画传输、分享和 OTA 回调仍需平台/固件确认。
- DP 116 `plant_variety` 已按可上报可下发处理：后端植物 `tuYaRemark` 是下发值，绑定成功后才下发，设备上报的已知标识符会反向更新当前植物；116 为空即「这台花盆还没有植物」。绑定时 116 与 161 `plant_type`（后台植物分类，enum 1/2/3）打包成同一条指令下发，后台没配分类时只发 116 并在结果里说明。162 `plant_confirm` 是数值：0 正常 / 1 异常 / 2 确认 / 3 忽略，0 和 1 由设备上报、2 和 3 由 App 下发，设备没上报过时按 0 处理；设备报 1 时不上报新植物标识，等 App 下发 2（改用盆里那株并重新上报 116）或 3（保持旧的 116）。163 `plant_detect_switch` 是自动检测植物开关，**平台尚未导出，DP 号是本地占位**。
- DP 140 校准固定依次发送 `step0`、`step1`、`step2`、`step3`，取消或在最终完成卡片尚未确认 `step3` 时关闭都发送 `step5`；`step4` 保留且不调用。
- 温度、湿度、电量、PPFD、DLI 没有历史功能点，真机上这几条曲线是空态而不是曲线；设备图片已可在 APP 后端上传/列出/删除——2026-09-08 起列表 `getUserProductImgList` 与上传 `setUserProductUpload` 都按涂鸦 `deviceId` 传参，不再先用 `getUserProductList` 换后端 `userProductId`（设备档案由涂鸦提供）——但 142/143/144 从云端 URL 下发到硬件的协议仍待确认。
- 2026-09-03 核验：`https://api.yikaltd.com` 已恢复，`/v2/api-docs` 与写死的临时地址 `http://120.25.227.36:8601` 返回同一份契约（123 条路径），`ApiConfig._temporaryBaseUrl` 及配套的 Android network-security-config、iOS ATS 例外可以按其 TODO 回滚。仍未使用真实账号执行写接口，真机端到端联调未完成。
- 验证码登录的自动注册复用的是同一条验证码：登录接口先判验证码（未注册手机号配错误验证码回的是「验证码错误」，说明验证码在账号查找之前判），失败后再调注册接口。若后端在验证码判过之后即作废，补注册会以「验证码错误」失败——这条只在 mock 上验证过，真机需要用真实短信确认。
- 配网三页已改为真实 `scanWifi` / `pairViaHotspot`（取令牌 → 连热点 → `pairWifiDevice`）链路。热点识别前缀已放宽到忽略分隔符的 `smartlif`（含量产件上见到的 `SmartLift-…`）、`tuya`、`ysplanter` 与 `ty_`/`ty-`，并且不再是门禁；2026-09-08 起搜索页在 45 秒窗口内反复扫描（间隔 2 秒），扫到设备热点就直接进选择页，窗口走完才给「未发现配网中的设备」，且不再显示扫描台数、手机当前连接和「从附近网络中手动选择设备」，选择页也去掉了「显示附近全部网络」和「设备已在配网状态，继续」；Android 桥接的 `scanWifi` 现在等一轮 `SCAN_RESULTS_AVAILABLE` 广播（最多 5 秒）再回，避免返回设备进入配网状态之前的缓存。iOS 不返回附近网络列表，搜索与选择页在 iOS 上只能走「手动继续」。 2026-09-09 起「连接Wi-Fi」页的 Wi-Fi 名称不再吃 `FlowerpotState.wifiScan` 的旧快照：进页面强制重扫，回到前台（`resumed`）再刷新一次，只在输入框为空或内容仍是上次自动填入值时才覆盖，用户自己输入 / 从「切换」选过的名称与重试带入的值都保持不动；配网进行中不刷新。
- 154/155/157/158/159 都是 raw 功能点，当前代码上报按 base64 解、下发按十六进制串写（`TuyaMemorialCodec.encodeRaw`），真机未验证。设备不回报整份自定义纪念日列表；当前已接后端纪念日接口，后端会话可用时分配 id、保存并刷新列表，本地 `deviceMemorials` 是缓存，后端不可用时保留本地路径。退出登录暂不清此缓存，账号隔离及迟到响应仍需加固。
- 2026-09-03 的两轮配网改动都只做了静态复核，`flutter test` 与真机均未跑（本机没有 Flutter 工具链）：热点识别放宽、选择页原始扫描结果回退、Android `scanWifi` 等待新一轮扫描结果，以及同日更早补的失败释放（`PairingResult` 包装、`cancelPairing`、Dart 侧 `leaveDeviceHotspot`）与手动回落路径。
- iOS 桥接已补齐配网前置、`joinDeviceHotspot`（`NEHotspotConfigurationManager`，需要 Hotspot Configuration entitlement，未配置时回 `hotspot_join_unsupported` 走手动路径）、`cancelPairing`、DP 上报与 OTA，但 iOS 侧全部改动尚未经过 Xcode 编译或真机验证；`createShareLink` 在 iOS 上仍是明确错误码（Home SDK 只有按账号分享）。
- 不要根据旧历史文档恢复已删除的平台文件；每次任务以实时 Git 状态确认工作区所有权，不将某次“有未提交改动”的状态视为跨环境事实。
- 2026-09-05 源码评审发现明文回落、URL 携带令牌、安全组件副本仍被 Git 跟踪、资料刷新会话竞态、写请求网络异常重试、体验模式退出未恢复真实仓库及配网销毁通知异常。静态分析有 2 warning / 1 info，全量测试有失败且运行未正常结束；本轮未修代码、未构建发布包。依据和整改优先级见 `docs/RELEASE_READINESS_REVIEW.md`，实际验证见对应历史记录。

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
