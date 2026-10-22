# Android / iOS 发布、健壮性与性能评审

> 状态：Tracking
> 核验日期：2026-09-05
> 基线：`main` / `2a8b5a336216d0cc4fb12a9e90cb8a3ff352b038`
> 范围：Flutter 客户端、原生桥接、平台配置、现有测试与 Active 文档
> 本轮只做评审及文档校正，以下代码整改尚未实施。

## 结论

保留 Flutter + Kotlin/Swift 涂鸦 SDK 桥接。现有分层、设计系统、HTTP 连接复用、DP 事件推送、配网取消和 OTA 成功回执机制值得保留。接近原生体验的重点是启动、局部刷新、系统交互和真机异常恢复。

当前不具备“已验证可正式发布”的证据：存在明文网络回落、安全组件被 Git 跟踪、会话竞态及测试失败；iOS 尚缺当前版本的 Xcode 编译、签名归档与真机业务验证。Windows 上无法完成 iOS 归档。本轮未生成 APK/AAB/IPA。

本文的“确认”表示源码或测试证据明确，不代表已在生产环境利用；性能优化项尚无真机耗时基线，不给出虚构提升百分比。服务端不在本仓库，不能据客户端审查断言其存在越权或数据库漏洞。

## 发布前优先处理

| 编号 / 优先级 | 证据与触发条件 | 建议与验收 |
| --- | --- | --- |
| S1 / P0 | `core/network/api_config.dart:11,24`：缺少 `API_BASE_URL` 时落到临时 HTTP。Android 为该 IP 放行明文；`ios/Runner/Info.plist` 全局设置 `NSAllowsArbitraryLoads=true`。账号、验证码、令牌及后端返回的映射凭据可能经明文链路传输。 | 正式模式要求显式 HTTPS 源站，缺失或非 HTTPS 时构建失败；联调例外限定开发构建。恢复 HTTPS 前先验证服务可用性；验证 release 的实际 Manifest/Info.plist 和抓包结果。不能仅改一条打包命令后留下危险默认值。 |
| S2 / P0 | `git ls-files` 确认 `assets/Android_SDK1/security-algorithm/security-algorithm-1.0.0-beta.aar` 仍被跟踪，违反接入文档的应用专属材料管理约定。当前通配忽略规则已存在，但不会移除已跟踪文件。 | 保留受控本机副本后移出 Git 跟踪；检查仓库及下载包传播范围，按供应商机制评估是否需重发组件/轮换关联凭据。历史清理需协调所有克隆和分支。仅删除当前文件或增加 ignore 不会清除历史。本轮未读取组件内容、删除文件或重写 Git 历史；不能据此认定 AppSecret 已泄漏。 |
| S3 / P1 | `core/network/api_client.dart:171` 将 `userToken` 加入 `/Client/` URL，同时也发请求头；本地日志脱敏不保护网关访问日志、代理及监控 URL。`api_session.dart:53` 用 SharedPreferences 存令牌，写入/删除异常被吞掉。 | 与后端确认只用鉴权头；后端和网关同步脱敏。敏感凭据迁移至 Keychain / Android Keystore 支持的安全存储，普通偏好继续保留；覆盖旧令牌迁移、备份恢复、写盘失败与退出后重启。服务端短期令牌和失效机制一起验收。 |
| R1 / P1 | `ApiClient.postJson` 默认允许超时重试；`_sendWithRetry:212` 对 ClientException/IOException 的重试不受 `retryOnTimeout=false` 控制。`sendSms:362` 未禁用超时重试。服务端已执行但响应断开时，注册、绑定、纪念日等写操作可能再次发送。 | 显式区分只读、幂等写、非幂等写；写请求默认不自动重试，确需重试则后端实现幂等键。统一总超时与真正的请求取消。模拟“服务端已提交、客户端丢失响应”，断言只产生一次业务记录；短信也由服务端限流。 |
| R2 / P1 | `state.dart:1595` 的 `refreshUserInfo` 在 await 前保存旧 `_user`，返回后无会话代次检查即写回。退出/切换账号期间旧响应迟到，可以把旧用户重新写回内存。`ApiClient._parse:232` 也会无条件用任意请求的 401 清掉当前令牌。 | 每次请求捕获账号、令牌版本和 session epoch；返回、鉴权失效及异步副作用仅作用于原会话。退出优先清空本地身份，网络退登独立收尾。补“旧成功响应晚于退出”和“旧 401 晚于新登录”的确定性测试。当前已有设备刷新 epoch 防护，应扩展到资料、纪念日、固件与网络层。 |
| R3 / P1 | `PairingPage.dispose:81` 调 `state.cancelPairing`，后者先同步 `_setPairingStage` → `notifyListeners`。现有“leaving the page during pairing cancels it”测试复现 widget tree locked 异常。 | 原生资源取消必须及时；把资源释放与 UI 状态通知拆开，避免在 widget 销毁期间同步通知仍在树中的监听者。验证系统返回、主动取消、切后台、销毁、迟到回调，保证无异常且网络绑定解除。不能通过删掉取消逻辑消除测试失败。 |
| R4 / P1 | `tuya_repository.dart:233` 通用 MethodChannel 调用没有超时；只有热点/配网部分路径有截止时间。初始化等待 `currentUser/getDevices` 等回调，普通 `_guard` 又使用全局 busy。SDK 漏回调可能持续卡闪屏或所有写操作。 | 为方法按职责设截止时间，初始化使用可恢复状态和单次执行的 Future；必要时原生完成取消与只回复一次。Dart Future 超时不等于原生操作已取消，晚到结果必须用 operation ID 丢弃。退出和取消不能被长任务锁阻断。 |
| R5 / P1 | `state.dart:349` 体验模式替换 `_repository` 为 Mock；`logout/_clearLocalSession` 只重置 demo 标志，没有恢复真实 Repository。退出体验后同进程再次登录仍可能走 Mock 设备链。 | 明确 demo/prod 容器的生命周期，退出体验重建生产状态和订阅；若正式产品无需体验入口，在生产构建关闭。补“真实模式 → 体验 → 退出 → 真实登录”回归。它是模式隔离问题，不是已证实的后端鉴权绕过。 |
| R6 / P1 | 原始设备事件的 `handleError` 吞掉所有通道异常；后续 `.map(_deviceUpdate)` 的解析异常不在这层保护内，State 的两个 listen 未提供 onError。 | 对不支持事件的 Mock 环境和生产断流分别处理；异常数据逐条隔离、记录脱敏诊断并恢复订阅/拉取快照。补损坏 DP、非预期字段类型、断流、重连及重复事件测试。 |
| B1 / P1 | iOS 已调用 NEHotspotConfigurationManager，但版本库未见 Runner 的 entitlements 文件及 `CODE_SIGN_ENTITLEMENTS` 设置；分享链接、图片直传桥接明确返回未支持错误码。 | 在 macOS 配置 Hotspot Configuration、按需求配置 Access WiFi Information、描述文件及定位授权流程，再验证最终签名 entitlement。保留手动配网回退。跨端分享统一产品契约，图片 URL 到设备协议与固件确认后再宣称完成。 |

P0 表示正式发布前必须关闭的风险，不代表已经发生攻击。P1 表示稳定性或生产功能阻塞，下一轮集中整改。

## 性能与接近原生体验

| 改进方向 | 当前依据 | 实施方式 |
| --- | --- | --- |
| 冷启动 | 闪屏最少 1800ms，退出动效 1100ms；`initialize` 等待设备列表、用户资料和 `_syncBackendDevices` 才完成。后者逐设备串行取详情/植物。 | 首屏与数据加载解耦：先恢复必要身份，再展示壳层与局部加载/缓存，后台刷新。减少强制等待；保留已确定的视觉设计，缩短动效需体验验收。设备资料批量接口优先，否则限定 3–4 个并发并保留 epoch 检查。 |
| 局部更新 | `FlowerpotApp.build:166` 监听整个 State，重建 MaterialApp 和主题；FlowerpotScope 也广播同一 notifier。设备 DP、OTA、busy 等互相影响构建范围。 | 先拆 AppSettings/Auth、DeviceStore、Pairing、OTA 的通知边界；以 deviceId/字段选择订阅。高频传感器显示可合并约 100–200ms，解绑、错误与 OTA 终态立即处理。无需先全量更换状态管理框架。 |
| 图片内存 | 图库 `Image.network/Image.file` 无解码尺寸限制；上传入口只有 imageQuality，没有尺寸/字节边界。当前 images 共 103 个文件、约 4.34 MiB，仅为源资产统计，不是 APK 包体。 | 按缩略图物理像素设置 cacheWidth/cacheHeight，上传限制尺寸、格式、数量和字节数；确需编码的重任务再放 isolate。按需缓存并设置上限，不缓存携带敏感 URL 的跨账号资源。文件体积小不代表解码内存小，例如 4000×3000 RGBA 约 45.8 MiB。 |
| 报表健壮性 | `reports_page.dart:109` 对 `!snapshot.hasData` 一律转圈，没有 hasError 分支；只首次和切范围加载，历史 DP 推送后已打开曲线可能仍旧。 | 明确加载/失败/空/有效状态，失败可重试；以相关历史版本刷新，避免所有设备上报都重新取数。 |
| 平台操作感 | 现有 Material 3 与 SafeArea 可保留；未发现应用级生命周期恢复协调；MaterialApp 设置 locale，但未配置完整本地化 delegates，页面仍有大量中文常量。 | 补 iOS 侧滑返回、系统返回/Android 预测性返回、键盘避让、系统分享、触感、读屏、动态字体和减少动态效果。用 ARB 与 Flutter 本地化覆盖中英文。保留品牌 UI，通过平台行为适配改善体验。 |
| 可观测性 | 有异常转 ActionResult 与开发日志；未发现集中 Flutter/异步错误采集及原生崩溃链路。 | 记录脱敏的操作 ID、阶段、耗时、结果码和构建版本；在隐私允许的前提下接入崩溃/ANR 监控，保留 Dart 与原生符号文件。SDK 初始化早于登录页同意操作，需抓包核实初始化阶段数据行为，再按 SDK 支持的隐私初始化流程调整。 |

先在中低端 Android 真机及 iPhone 上建 Profile 基线；Debug 帧率不能代表发布性能。候选验收目标（需要基线校准）：60Hz 设备 UI/raster 各阶段 P95 不超过约 16.7ms，120Hz 对应约 8.3ms；弱网不无限阻塞首屏；连续打开关闭图库 20 次无持续内存增长。首次启动、缓存启动、离线启动分开统计，不把网络握手算作 Flutter 渲染耗时。依据：[Flutter 性能实践](https://docs.flutter.dev/perf/best-practices)、[Profile 性能视图](https://docs.flutter.dev/tools/devtools/performance)。

## 双端构建与发布建议

1. 建立显式 development/staging/production 配置；production 校验真实 Tuya 模式、HTTPS、禁用联调入口、签名与组件齐全。当前 SDK 是否链接依赖本机 AAR/podspec 是否存在，Dart 模式又由另一开关控制，需统一校验以避免同一提交在两台电脑产生不同能力的包。
2. 固定 Flutter 版本，保留 pubspec.lock；iOS 首次成功解析并验证后提交 Podfile.lock。版本号/build number 由发布流水线管理，密钥从受控渠道注入。当前 pubspec 的 SDK 范围不能替代 Flutter 工具链锁定。
3. Android 使用 release AAB 面向 Google Play；直接分发使用按 ARM ABI 拆分的 release APK。涂鸦 SDK、证书指纹和 Google Play App Signing 最终分发证书需匹配。检查混淆后的反射桥接，不能只用 Debug 通过判断 Release 可用。
4. 检查包内所有原生 `.so` 的 16KB 兼容性，包括第三方安全组件、C++ 运行库与涂鸦依赖；升级 Flutter/NDK 并不会重编第三方预编译库。当前 `pickFirst` 对重复原生库的选择也需验证。见 [Android 官方 16KB 指引](https://developer.android.com/guide/practices/page-sizes)。
5. iOS 在 macOS + Xcode 上完成真实 SDK 构建、签名 Archive、IPA 导出与 TestFlight 真机验收。检查 SDK 与插件的最终隐私清单及 Required Reason API 声明，不能仅凭仓库未见清单断定归档缺失。见 [Flutter iOS 发布](https://docs.flutter.dev/deployment/ios)、[Apple Hotspot entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.hotspotconfiguration)、[Apple Required Reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。
6. 审计最终依赖树/SBOM，再判断已知漏洞及可达性。当前 Gradle 固定 fastjson 与 okhttp 等依赖，不应仅凭版本年龄认定有可利用 CVE，也不应绕过涂鸦兼容矩阵盲升。MD5 是当前后端密码契约，应与后端一起改造；客户端自行改成 SHA-256 不能替代服务端安全密码存储和 TLS。

配置齐备并完成整改后的命令参考（本轮未执行构建）：

```bash
flutter build appbundle --release --dart-define=TUYA_ENABLED=true --dart-define=API_BASE_URL=https://api.yikaltd.com --dart-define=TUYA_DEBUG_TOOLS=false
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --dart-define=TUYA_ENABLED=true --dart-define=API_BASE_URL=https://api.yikaltd.com --dart-define=TUYA_DEBUG_TOOLS=false
# 以下命令在配置完成的 macOS/Xcode 环境执行
flutter build ipa --release --dart-define=TUYA_ENABLED=true --dart-define=API_BASE_URL=https://api.yikaltd.com --dart-define=TUYA_DEBUG_TOOLS=false
```

HTTPS 域名取自已有文档的 2026-09-03 核验，本轮未再次探测业务服务器。实际发布前必须重新核对，命令本身不代表平台材料或业务链路已验证。

## 验证与覆盖边界

- 本机：Windows，Flutter 3.44.6 / Dart 3.12.2。开始时工作树干净；CodeGraph status 报索引最新。
- `flutter analyze --no-pub`：退出码 1，2 个 warning（memorial_edit_page 未使用 height 参数、pairing_page 未使用 action 参数）和 1 个 info（后端 repository 的 null-aware element 风格）。未报编译级 error。
- 全量测试：两次运行均记录到 271 项通过、32 项失败后未正常结束，第二次已指定单项 60 秒超时，仍未解决退出问题；已清理本轮测试进程。不能将此计数当作完整套件通过率，实际操作见 [本次历史记录](history/2026-09/2026-09-05-release-readiness-review.md)。
- 已确认配网退出通知时机异常。OTA 的多项测试 helper 只调用 refreshDevices，未调用 initialize 建立事件订阅；其失败不能作为真机 OTA 损坏结论。多项 UI 用例仍断言旧文案/元素，需与当前 PRD 对照后更新。
- 未运行 Android Gradle 构建、iOS 编译、真机性能/配网/OTA、渗透测试和依赖漏洞数据库扫描；没有调用短信、注册、设备控制或其他线上写接口。
- 服务端专项验收另行安排：双测试账号验证设备/图片/纪念日资源所有权、令牌失效、验证码次数与频率、上传内容与大小、分享撤销及双系统注销一致性。客户端校验不能代替服务端授权。

SharedPreferences 官方也明确不应用于关键数据持久化，见 [插件文档](https://pub.dev/packages/shared_preferences)。移除全局 ATS 例外的依据见 [Apple ATS 配置](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads)。

## 实施顺序

第一批关闭 S1/S2/S3，修复会话竞态、写重试、体验模式退出与配网取消；用故障注入测试证明不会重复提交、不会恢复旧身份、不会残留热点绑定。

第二批让现有测试恢复可用，补原生调用截止时间、生产构建校验与 macOS/iOS 构建流水线；完成双端真实账号、设备和 OTA 闭环。不要把更新测试断言当作修复产品问题。

第三批在 Profile 数据支持下改启动与通知边界，再优化图片和平台交互。性能改造以局部替换、行为不变为原则，不建议此时重写整个状态层或改成两套纯原生应用。
