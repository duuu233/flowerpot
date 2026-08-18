# 涂鸦 Smart Life App SDK 配置

当前桥接按 Android Home SDK `thingsmart:7.5.1`、Expansion SDK `thingsmart-expansion-sdk:7.8.0` 与 iOS 7.5.x 结构准备。Home 版本以平台下载包内的 `thingsmart_home_sdk/dependencies.txt` 为准；两套 Android SDK 使用各自的版本号，不能共用一个版本变量。涂鸦应用的包名必须与本项目 `com.common.yikaltd` 一致；若要更换包名，应在创建 SDK App 和下载安全组件前完成。

## 1. 开发者平台

1. 创建“智能家居 / Smart Life App SDK”应用。
2. Android 包名填写 `com.common.yikaltd`，配置调试与发布证书 SHA-256。
3. iOS Bundle ID 填写 `com.common.yikaltd`。
4. 选择 Home SDK、业务拓展 SDK、设备配网、设备管理、设备分享、数据统计和 OTA 能力。
5. 开发阶段可用开发版；上架前需要按涂鸦政策构建正式版安全组件。

## 2. Android

平台当前会分别下载 `Android_SDK.tar.gz` 与 `security-algorithm.tar.gz`。从安全组件压缩包中解出 `security-algorithm-1.0.0-beta.aar`，重命名并放到：

```text
android/app/libs/security-algorithm.aar
```

原始下载包及安全 AAR 都是应用专属材料，不得提交。项目已忽略 `/assets/Android_SDK/` 和目标 AAR。将 `Android_SDK.tar.gz` 版本目录中的完整 `assets/` 与默认语言文件 `res/values/strings.xml` 合并到：

```text
android/app/src/main/assets/
android/app/src/main/res/values/strings.xml
```

其中 `module_app.json` 与 `x_platform_config.json` 是 Expansion/BizBundle 的服务化配置，SDK 更新后必须使用同一次平台构建生成的新文件同步替换。当前 App 界面仍由 Flutter 实现，因此不复制可选的 `res/values-*` 多语言目录；当前下载包的土耳其语资源存在 `ExtraTranslation`，完整复制会使 Release Lint 失败。后续若改用 Android UI BizBundle，应升级到资源完整的业务包后再引入所需语言。

在 `android/local.properties` 追加（该文件不提交）：

```properties
tuya.appKey=YOUR_ANDROID_APP_KEY
tuya.appSecret=YOUR_ANDROID_APP_SECRET
```

安全 AAR 存在时，Gradle 会自动启用 `thingsmart:7.5.1` 与 `thingsmart-expansion-sdk:7.8.0`。没有 AAR 时不下载 SDK，方便普通 UI 构建和测试。Gradle 在配置阶段会打印当前状态（是否链接 SDK、密钥是否缺失、ABI 提示），可据此判断本机材料是否齐全。

涂鸦要求 `ThingHomeSdk.init` 在 `Application.onCreate` 中执行，因此初始化由 `FlowerpotApplication` 负责，`AndroidManifest.xml` 的 `android:name` 指向该类而不是 Flutter 的 `${applicationName}` 占位符。初始化成功后同样初始化可用的 `ThingOptimusSdk`。初始化是尽力而为的：缺少 AAR、缺少密钥或 ABI 不支持时只记录原因并让 App 正常启动，Flutter 侧调用任意桥接方法时会收到对应错误码（`sdk_unavailable`、`credentials_missing`、`sdk_abi_unsupported`、`security_component_mismatch`）。

项目 `minSdk` 为 24：满足当前 Flutter 图片选择插件要求，也高于涂鸦 Android SDK 的最低要求 23。

涂鸦安全组件与 SDK 原生库只提供 `armeabi-v7a` 与 `arm64-v8a`，没有 x86/x86_64。因此 `TUYA_ENABLED=true` 需要满足下列任一条件：

- API 30 及以上、实际启用了 ARM 转译且能按 ARM ABI 启动应用的 x86_64 模拟器镜像；
- arm64 模拟器镜像；
- 真机。

仅看到 `Build.SUPPORTED_ABIS` 包含 `arm64-v8a` 仍不足以证明通用 APK 会按 ARM 运行：Flutter 通用 Debug APK 同时带有 x86_64 引擎时，部分模拟器会优先以 x86_64 进程启动，随后在加载涂鸦 ARM 库时报告 `libc++_shared.so not found`。仅传 `--target-platform android-arm64` 会限制 Flutter 引擎，但依赖 AAR 仍可能把其他 ABI 的 JNI 文件装入通用 APK；本机 OPPO R11 Plus / 夜神 Android 12 实例应同时使用 `--split-per-abi` 生成真正的 arm64-only APK，并在安装时显式指定 ABI：

```bash
flutter build apk --debug --split-per-abi --target-platform android-arm64 --dart-define=TUYA_ENABLED=true --no-pub
adb -s <device-serial> install -r --abi arm64-v8a build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
adb -s <device-serial> shell am start -n com.common.yikaltd/.MainActivity
```

若显式安装后仍出现架构不匹配，应改用 arm64 模拟器或真机。在不满足条件的镜像上，Application 初始化会记录 `sdk_abi_unsupported`；若连 Flutter 引擎本身都无法被该镜像转译，Activity 仍可能在进入 Flutter 前失败。Mock 业务模式（不传 `TUYA_ENABLED`）不依赖涂鸦调用；本地 AAR 已存在时 Application 仍会尝试初始化 SDK，但失败只记录日志，不阻止通用 Flutter APK 继续运行 Mock UI。

若启动时报 `security_component_mismatch` 或日志中出现 `AEADBadTagException`，表示安全组件无法解密当前应用配置。依次确认 AppKey、AppSecret、包名 `com.common.yikaltd`、APK 实际签名 SHA-256 与平台完全一致，然后在同一个 SDK 应用下重新构建并下载 `security-algorithm.tar.gz`。安全组件与 AppKey/包名/证书必须来自同一次平台配置快照，只更新其中一项会继续报同一个错。不要在工程任意目录额外放置旧版 `t_s.bmp`；安全图片已封装在新安全 AAR 内。

签名策略：`android/key.properties` 存在且四项完整时，debug、profile 与 release 统一使用该正式证书，使运行中的 App 指纹与平台登记的 SHA-256 一致。缺少该文件时，debug 与 profile 回退到 Android 默认调试证书（UI 与 Mock 模式照常运行，真实涂鸦调用会因指纹不匹配失败），release 仍然直接失败、不会静默降级。模板见 `android/key.properties.example`（`android/key.properties` 已忽略提交）：

```properties
storeFile=path/to/release.jks
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
storePassword=YOUR_STORE_PASSWORD
```

`android/app/proguard-rules.pro` 已挂到 release 构建类型。原生桥接靠反射解析涂鸦类与回调接口，压缩开启时必须保留 `com.thingclips.**`。

不要在 `android.defaultConfig` 中手动配置 `ndk.abiFilters`。Flutter Gradle 插件会根据构建参数管理 ABI；手动过滤会与 `--split-per-abi` 注入的拆分配置冲突。生成按 ABI 拆分、使用正式证书签名的 release APK：

```bash
flutter build apk --release --split-per-abi --no-pub
```

该命令只决定 Android release 构建和拆包方式，不会自动启用真实涂鸦链路。真实设备生产构建仍需按第 5 节启用 `TUYA_ENABLED`，并完成密钥、安全组件、DP 与真机验证。

`StaticPreviewConfig.enabled` 只影响 Mock 后端是否预置演示设备，不影响真实模式，真机联调前不需要改它。但登录页的「体验模式」按钮在任何构建下都会把仓库切换成 `MockTuyaRepository`；真实链路验证必须走正常登录，不要用该入口。登录页另有「涂鸦 SDK 联调」入口，见 5.3；它使用当前仓库，不做任何切换。

### 2.1 新开发电脑的一次性配置清单

下列非敏感配置已经进入 Git，拉取仓库后不需要再次手工配置：

| 内容 | Git 中的权威位置 |
| --- | --- |
| 包名 `com.common.yikaltd`、minSdk、签名选择逻辑 | `android/app/build.gradle.kts` |
| Home SDK 7.5.1、Expansion SDK 7.8.0 与依赖排除规则 | `android/app/build.gradle.kts` |
| `FlowerpotApplication`、Manifest 元数据占位符与桥接代码 | `android/app/src/main/` |
| Expansion SDK 的 `module_app.json`、`x_platform_config.json`、主题和字体资源 | `android/app/src/main/assets/` |
| 默认 Android 字符串资源 | `android/app/src/main/res/values/strings.xml` |
| 本机属性模板 | `android/local.properties.example` |
| 签名属性模板 | `android/key.properties.example` |
| arm64 Debug 构建、安装与日志命令 | 本文第 2 节和第 5 节 |

下列内容禁止提交到 Git。换电脑后必须从涂鸦平台、密码管理器或其他受控渠道取回，并在本机配置一次；不要把真实值发到聊天、Issue、提交信息或 Markdown：

| 本机目标 | 需要填写或复制的内容 | 原因与注意事项 |
| --- | --- | --- |
| `android/local.properties` | `sdk.dir` | Android SDK 的本机绝对路径，每台电脑可能不同。 |
| `android/local.properties` | `flutter.sdk` | Flutter SDK 的本机绝对路径，每台电脑可能不同。 |
| `android/local.properties` | `tuya.appKey` | 从包名为 `com.common.yikaltd` 的同一个涂鸦 SDK App 取回，不提交真实值。 |
| `android/local.properties` | `tuya.appSecret` | 涂鸦应用秘密，只能保存在本机受控文件或密码管理器中。 |
| `android/app/libs/security-algorithm.aar` | 当前 SDK App 生成的安全组件 | 必须与 AppKey、包名和签名证书属于同一份平台配置。 |
| 本机安全目录或已忽略的 `assets/AndroidKeys/` | 正式签名 JKS | 属于签名材料；通过安全渠道从原持有人处取回，绝不提交。 |
| `android/key.properties` | `storeFile`、`keyAlias`、`keyPassword`、`storePassword` | `storeFile` 指向上面的 JKS；其余字段从密码管理器取回。 |
| 已忽略的 `assets/Android_SDK/` | 涂鸦平台原始下载包（仅 SDK 升级时需要） | 当前构建需要的抽取后资源已经进入 `android/app/src/main/`，普通换电脑不必复制原始压缩包。 |

`flutter.buildMode`、`flutter.versionName` 与 `flutter.versionCode` 由 Flutter 构建过程生成，不要从另一台电脑复制，也不需要手工输入。

Windows 公司电脑首次配置可按下面的顺序执行：

```powershell
git pull
codegraph sync .
Copy-Item android\local.properties.example android\local.properties
Copy-Item android\key.properties.example android\key.properties
```

然后只在本机编辑这两个被忽略的文件：

```text
android/local.properties
  sdk.dir
  flutter.sdk
  tuya.appKey
  tuya.appSecret

android/key.properties
  storeFile
  keyAlias
  keyPassword
  storePassword
```

从安全目录复制安全组件；JKS 可以留在安全目录，只要 `storeFile` 指向它：

```powershell
New-Item -ItemType Directory -Force android\app\libs
Copy-Item <安全组件来源路径> android\app\libs\security-algorithm.aar
```

配置后执行一次无泄密检查和构建。下面的命令只检查文件是否存在，不会打印密钥或密码：

```powershell
Test-Path android\local.properties
Test-Path android\key.properties
Test-Path android\app\libs\security-algorithm.aar
flutter clean
flutter pub get
flutter build apk --debug --split-per-abi --target-platform android-arm64 --dart-define=TUYA_ENABLED=true --dart-define=TUYA_DEBUG_TOOLS=true --no-pub
```

最终使用 `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`。若构建控制台没有出现 `[flowerpot] Tuya SDK enabled`，先按上表检查安全 AAR 和两个涂鸦字段，不要通过取消 Git 忽略来绕过检查。

## 3. iOS

解压平台生成的 `ios_core_sdk.tar.gz`，整理为：

```text
ios/TuyaSDK/ThingSmartCryption.podspec
ios/TuyaSDK/Build/...
```

复制配置模板并填写密钥：

```bash
cp ios/Flutter/Tuya.xcconfig.example ios/Flutter/Tuya.xcconfig
cd ios && pod install
```

`Tuya.xcconfig` 内容：

```text
THING_SMART_APPKEY=YOUR_IOS_APP_KEY
THING_SMART_APPSECRET=YOUR_IOS_APP_SECRET
```

## 4. 产品 DP

在 `lib/src/tuya/tuya_config.dart` 校正 `TuyaConfig.dp`。当前 101–123 是代码占位，不应直接发布：

- 传感器：水仓、土壤、照度、PPFD、温度、湿度、电池、充电。
- 控制：亮度、声音、触摸、振动、灵敏度、定时行为、天气、温标、时钟。
- 维护：水位校准、系统修复。

同时确认值类型（bool/value/enum/string/raw）、范围、步进和倍率。DP 类型错误会导致指令被 SDK 或设备拒绝。

## 5. 运行

### 5.1 模拟器上跑 UI / Mock 模式

```bash
flutter pub get
flutter run
```

不传 `TUYA_ENABLED` 时使用 `MockTuyaRepository`，业务操作不会调用涂鸦桥接。原生 SDK 是否编入 APK 只取决于本机是否存在 `android/app/libs/security-algorithm.aar`：没有 AAR 时完全不解析 SDK；已有 AAR 时 `FlowerpotApplication` 会尽力初始化，失败只记录日志，不影响 Mock UI。缺少 `android/key.properties` 时 debug 会用默认调试证书继续构建，只在控制台打印一条提示。

### 5.2 真实模式

前置条件（缺任意一项都会在 App 内以对应错误码返回，不会崩溃）：

| 前置条件 | 缺失时的错误码 |
| --- | --- |
| `android/app/libs/security-algorithm.aar` | `sdk_unavailable` |
| `android/local.properties` 的 `tuya.appKey` / `tuya.appSecret` | `credentials_missing` |
| 设备/模拟器支持 `arm64-v8a` 或 `armeabi-v7a` | `sdk_abi_unsupported` |
| 安全组件与 AppKey、包名、证书 SHA-256 属于同一份平台配置 | `security_component_mismatch` |

```bash
flutter run --dart-define=TUYA_ENABLED=true
```

排查时按包名过滤日志，标签为 `FlowerpotTuya`；日志只输出类名与错误码，不含任何密钥。

### 5.3 登录页的 SDK 联调入口

登录页底部除「体验模式」外还有「涂鸦 SDK 联调」入口，指向 `AppRoutes.tuyaDebug`（`/devtools/tuya`，登录前即可进入）。该页直接调用账号链路，不受协议勾选和产品文案约束，并显示每次调用的原始失败码，用于在走配网流程之前确认平台配置：

- 运行环境：`TUYA_ENABLED`、当前仓库是原生桥接还是 Mock、初始化状态、方法通道、默认家庭名与当前会话。
- 账号参数：手机号（国家码 86）或邮箱（国家码 1），对应桥接的手机与邮箱接口。
- 注册：发送注册验证码（type 1）与「注册并登录」；注册成功后 SDK 直接持有会话，不需要再登录。
- 登录：发送登录验证码（type 2）、验证码登录、密码登录。
- 会话与设备：初始化自检、查询会话、拉取设备列表、退出登录。「拉取设备列表」会先查询家庭并在没有家庭时自动建家，是配网前必须先跑通的一步；返回 0 台说明链路通了、账号下还没有绑定设备。
- 配网：Wi-Fi 名称、密码与 EZ/AP 模式，直接调用 `pairWifiDevice`（超时 120 秒）。失败只写进日志并带原始错误码，不跳转到配网失败页，便于连续重试和对照错误码。
- 调用日志：时间、结果、失败码与脱敏账号，可复制或清空。页面与日志只显示脱敏账号，不显示密码、验证码或密钥。

已登录时冷启动会直接进入 `AppShell`，因此「我的」页标题栏右侧同样有一个联调图标入口，不需要退出登录就能回到该页。

两个入口在 debug 与 profile 构建中始终可见；release 构建必须显式开启：

```bash
flutter build apk --release --split-per-abi --dart-define=TUYA_DEBUG_TOOLS=true --no-pub
```

未开启时入口隐藏，`/devtools/tuya` 也会回落到登录页。Mock 模式下该页会明确提示调用只命中 Mock 后端，不能作为真实链路结论。

## 6. 当前桥接边界

`android/app/src/main/kotlin/com/common/yikaltd/MainActivity.kt` 中的桥接不硬编码涂鸦回调接口名：先按方法名与参数个数解析目标方法，再用该方法声明的最后一个接口参数生成动态代理。因此 `logout`（`ILogoutCallback`）与 `cancelAccount`（`IResultCallback`）、`getOtaInfo`、`setOtaListener` 等签名不同的接口能共用同一套调用代码，SDK 升级改名也不会静默失效。Expansion SDK 7.8.0 的初始化声明为 `ThingOptimusSdk.init(Context)`；反射查找必须使用声明类型 `Context`，实际参数仍可传入 `Application`。

已接通：账号（验证码、登录、注册、找回密码、改昵称、退出、注销）、家庭查询与自动建家、AP/EZ 配网、设备列表、DP 下发、重命名、解绑、恢复出厂、OTA 查询与升级。

尚未接通，调用会返回明确错误码而不是假数据：

- `getStatistics` → `service_configuration_required`：报表历史数据需要在平台开通统计服务并接入统计 API。
- `uploadAnimation` → `product_protocol_required`：动画同步需要 PID 对应的文件传输协议。
- `createShareLink` → `share_service_unavailable`：分享链接由业务拓展 SDK 提供，管理类包名需要在开通设备分享后核对。

还未实现的能力：

- 设备 DP 实时上报。当前只在 `getDevices` 时读取一次 `dps`，下发后 UI 不会收到设备主动推送的变化。接入时需要注册 `IDevListener` 并新增一条 Flutter 事件通道，同时扩展 `TuyaRepository` 契约。
- **设备发现**。桥接里没有任何扫描接口，`TuyaRepository` 也没有对应契约。**产品确认设备只支持 2.4GHz Wi-Fi 配网，没有蓝牙配网**，因此这里不应该去实现 BLE 扫描：EZ/AP 配网本来就没有「先扫描再选设备」这一步，设备是否在配网状态只能由用户看指示灯确认。配网动线中只有最后一步是真实的：

| 页面 | 现状 |
| --- | --- |
| `DeviceSearchPage`（搜索设备） | 纯动画，2 秒定时器后直接跳到选择页，不做任何扫描。 |
| `DeviceSelectionPage`（选择设备） | 写死的 `YSplanter-01/02/03` 与信号格；「连接」是 600ms 延时动画，不建立任何连接。选中的名字只作为文案传给下一页，不会进入 `PairingRequest`。 |
| `PairingPage`（连接 Wi-Fi） | **真实**：`pairWifiDevice` → `getActivatorToken` + `newMultiActivator`，当前固定 `TY_AP`。「切换」弹窗里的网络名同样是写死的示例。 |

配网前的运行时权限只申请 Wi-Fi 相关项：API 33 以下要求 `ACCESS_FINE_LOCATION`，API 33 及以上要求 `NEARBY_WIFI_DEVICES`（同时申请但不强制 `ACCESS_FINE_LOCATION`）。不要再把 `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` 加进配网前置检查：设备没有蓝牙配网，而这两项被拒绝会让整个配网直接返回 `permission_denied`。Manifest 中仍保留蓝牙声明（涂鸦 SDK 自身可能合并同名权限），但 App 不会主动申请。

因此真机配网必须手动输入设备实际所在的 2.4G Wi-Fi 名称和密码。默认仍是 AP 模式，需要先让手机连到设备热点；debug 构建在 Wi-Fi 页的「真实 SDK」标识旁提供 AP/EZ 选择器，可直接切到 EZ 快连再试，release 不显示该选择器。接入真实设备发现时，需要新增 `TuyaRepository` 契约、桥接扫描接口与事件通道，并替换上面两页的模拟实现。

### 6.1 模拟数据标识

`lib/src/design_system/widgets/feedback/mock_data_marker.dart` 提供三个开发期标识：`MockDataBanner`（整页或整块为模拟）、`MockDataBadge`（单个值为模拟）、`LiveDataBadge`（确实走了原生桥接）。它们与 SDK 联调入口共用 `DebugToolsConfig`：debug/profile 常显，release 需 `--dart-define=TUYA_DEBUG_TOOLS=true`，否则完全不渲染。

已标注的位置包括：配网三页、`AppShell`（Mock 后端时置顶横幅）、首页养护文案、设备列表、设备信息、五个状态页、设备设置与其他设置、植物选择与详情、动画、账号与安全、帮助、协议、关于、登录页的「体验模式」。新增页面时，只要数据不是来自真实 SDK 调用就应加上对应标识，不要让占位值以正常样式出现。

## 7. 发布前检查

- Android 包名、签名 SHA-256、AppKey/AppSecret、安全 AAR 完全匹配。
- 使用 `apksigner verify` 核对所有待分发 APK 的签名有效且证书一致。
- iOS Bundle ID、AppKey/AppSecret、ThingSmartCryption 完全匹配。
- 关闭 release SDK debug 日志。
- 购买/构建正式版 SDK，补齐隐私清单和第三方 SDK 清单。
- 验证 AP 配网、本地网络权限、设备分享深链、OTA 中断恢复与账号数据区域。
