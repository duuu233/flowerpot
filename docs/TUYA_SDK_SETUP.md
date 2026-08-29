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
ios/TuyaSDK/Build/ThingSmartCryption.xcframework/...
```

`ios/TuyaSDK/` 已在 `.gitignore` 中：这份安全组件与 AppKey、AppSecret、Bundle ID 绑定，和密钥同等重要，不进 Git、不外发。

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

Podfile 与 Android 一样是条件接入：只有 `ios/TuyaSDK/ThingSmartCryption.podspec` 存在时才声明涂鸦的 pod，否则工程仍能按 Mock 模式构建。版本跟随平台随安全组件一起下发的 Podfile——**当前是 `ThingSmartHomeKit ~> 7.8.0`**。安全组件是按某一条 SDK 线构建的，配错版本不会在 `pod install` 报错，而是在运行时失败。

同一份 Podfile 的 `post_install` 只在 SDK 真的接入时设置 `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`（涂鸦官方 Podfile 的要求，部分组件没有 arm64 模拟器切片，Apple Silicon 上要走 Rosetta）。没有安全组件时不设置，避免无谓地破坏普通 Flutter 模拟器构建。

两处 iOS 平台限制，接入前先知道：

| 能力 | 状态 |
| --- | --- |
| 附近 Wi-Fi 列表 | iOS 没有公开的扫描 API。`scanWifi` 只回当前网络名（`NEHotspotNetwork.fetchCurrent`，iOS 14+），列表恒为空、频段恒为未知。要读到当前 SSID 还需要在 Xcode Target 打开 **Access WiFi Information** 能力并授予定位权限；没开只是读不到，不会报错。 |
| 分享链接 | iOS Home SDK 的设备分享是**按账号分享**（`ThingSmartDeviceShare`），没有 Android 业务拓展 SDK 那种生成分享链接的接口。`createShareLink` 因此返回 `share_service_unavailable`，改造需要产品先决定分享页是否改成填写接收方账号。 |

## 4. 产品 DP

`lib/src/tuya/tuya_config.dart` 的 `TuyaConfig.dp` 是 PID `orhqsdjyigmh8bwa`（智能花盆test）在 2026-08-20 导出的功能点表，DP 101–150 共 50 条，键是涂鸦标识符本身，可以和平台导出逐行对照。原始导出件是 `assets/智能花盆test(orhqsdjyigmh8bwa)_08_20.xlsx`。换 PID 或改功能点后要重新导出替换整张表，不要手工改单行。

App 侧的命名不再直接当 DP 键用，两层映射都在同一个文件里：

- `TuyaConfig.setting`：可写设置 → 标识符；
- `TuyaConfig.history`：历史曲线 → 三个窗口的 raw DP；
- `TuyaConfig.settingDps(key, value)`：把一条设置编码成实际下发的 `Map<dpId, value>`，产品没有该功能点时返回 `null`，App 报 `unsupported_dp` 而不是发一条设备会拒绝的指令。

需要注意的类型细节，写错会被 SDK 或设备直接拒：

| 功能点 | 细节 |
| --- | --- |
| `air_temperature` (112)、`air_humidity` (114) | 倍数 1，设备传的是十倍整数。读除以 10、写乘以 10，映射在 `TuyaConfig.dpScale`。 |
| `nap_*_time` (126/127)、`night_sleep_*_time` (129/130) | 一个作息 = 两条 value DP，单位是「当天第几分钟」。App 里仍是 `HH:MM-HH:MM`，在 `settingDps` 与设备解析处两头换算。 |
| `temp_unit_convert` (146) | enum `C` / `F`，不是 `celsius` / `fahrenheit`。 |
| `time_format` (147) | enum `24h` / `12h`，与 App 取值一致。 |
| `plant_variety` (116) | string，可上报可下发。值来自后端植物字段 `tuYaRemark`；先完成用户植物绑定，再下发 116。设备上报已知标识符时 App 反向切换当前植物。 |
| `water_level_calib` (140) | enum：四次确认依次下发 `step0`、`step1`、`step2`、`step3`；取消下发 `step5`，`step4` 暂不调用。 |
| 131–139 | raw 历史包，格式见 `lib/src/tuya/tuya_history_codec.dart`。 |

表里没有对应功能点、界面上又存在的两处：**天气服务**（已从设置模型中删除）和**修复系统文件**（改为提示「系统修复暂未开放」）。要做就得先在平台加 DP。

五条产品口径，写在这里免得反复问：

- **146 温度单位**：DP 112 的单位列写的是 `°C/°F`，设备切到华氏后**上报值本身就是华氏**。所以 App 只跟着换单位标签，绝不再做一次换算；需要换算的是 App 自己那套摄氏阈值（18–28 ℃ 的舒适区、坐标轴上限、养护建议文案），换算集中在 `DeviceControlSettings.temperatureFromCelsius`。
- **147 时间格式**：下发之后 App 自身的时间展示跟随，`DeviceControlSettings.formatClock` 把 `HH:MM` 转成 12 小时制；写回设备的仍然是 24 小时制的 `HH:MM`，以及最终的「当天第几分钟」。趋势图的时间轴刻度仍固定 24 小时制。
- **141 恢复出厂 / 150 重新配网**：恢复出厂会先向设备下发 141，再调 SDK 的 `resetFactory` 解绑（设备离线或拒绝时不阻断解绑）；设备收到 141 后的具体行为待固件确认。重新配网**不需要额外下发 150**，触发时让设备重新走一遍配网流程即可。
- **116 植物品种**：后台 `tuYaRemark` 是固件识别的英文标识符，不使用数据库 id 或中文名。更换植物时先完成后端删除/新增，再下发；下发失败保留已成功的后端绑定并提示重试。
- **140 水位校准**：弹窗四个主操作与 `step0`–`step3` 一一对应，最后的「完成」也必须发送 `step3`；中途取消或在最终卡片改点「关闭」都发送 `step5`，任何路径都不发送 `step4`。

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
flutter run --dart-define=TUYA_ENABLED=true --dart-define=API_BASE_URL=https://your-api-origin.example
```

`API_BASE_URL` 填服务源站，不填 Swagger 页面路径。配置后，国内短信/登录/注册、用户设备、植物和设备图片走 `HttpAppBackendRepository`；国内登录返回的 `userNo` / `tuYaPwd` 会继续用于涂鸦登录。未配置时 REST Repository 禁用，便于 Mock UI 和独立涂鸦调试。当前提供的 `https://api.yikaltd.com` 在 2026-08-25 核验时返回备案阻断页，恢复可用 HTTPS 域名前不能视为真机接口联调完成；机器端口的 HTTP Swagger 只用于读契约，不作为生产地址。

排查时按包名过滤日志，标签为 `FlowerpotTuya`；日志只输出类名与错误码，不含任何密钥。

### 5.3 登录页的 SDK 联调入口

登录页底部除「体验模式」外还有「涂鸦 SDK 联调」入口，指向 `AppRoutes.tuyaDebug`（`/devtools/tuya`，登录前即可进入）。该页直接调用账号链路，不受协议勾选和产品文案约束，并显示每次调用的原始失败码，用于在走配网流程之前确认平台配置：

- 运行环境：`TUYA_ENABLED`、当前仓库是原生桥接还是 Mock、初始化状态、方法通道、默认家庭名与当前会话。
- 账号参数：手机号（国家码 86）或邮箱（国家码 1），对应桥接的手机与邮箱接口。
- 注册：发送注册验证码（type 1）与「注册并登录」；注册成功后 SDK 直接持有会话，不需要再登录。
- 登录：发送登录验证码（type 2）、验证码登录、密码登录。
- 会话与设备：初始化自检、查询会话、拉取设备列表、退出登录。「拉取设备列表」会先查询家庭并在没有家庭时自动建家，是配网前必须先跑通的一步；返回 0 台说明链路通了、账号下还没有绑定设备。
- 配网：先「扫描附近 Wi-Fi」再填 Wi-Fi 名称、密码与 EZ/AP 模式，直接调用 `pairWifiDevice`（超时 120 秒）。失败只写进日志并带原始错误码，不跳转到配网失败页，便于连续重试和对照错误码。旁边还有「获取配网令牌」，只有 AP 模式需要单独点，见下节。

「扫描附近 Wi-Fi」走的是 `scanWifi` 桥接方法（`WifiManager.startScan` + `scanResults`），不依赖涂鸦 SDK，SDK 未初始化时也能用。它有两个用途：确认手机当前连的是 2.4G 还是 5G（EZ 配网连在 5G 上必然失败），以及在 AP 模式下确认设备热点（`SmartLife-*`、`TY_*`）是否已经出现——这是配网前唯一能真实验证「设备已进入配网状态」的手段。点列表里的任意一项会把名称填进 Wi-Fi 名称输入框。

扫描受系统限制：Android 9 起每 2 分钟只允许前台应用扫描几次，超出后返回上一次的缓存结果；Android 9–12 还要求系统定位开关打开，否则返回 `location_disabled`；手机 Wi-Fi 关闭时返回 `wifi_disabled`。

### AP 模式必须先取令牌

`getActivatorToken` 是**云端调用**。AP 配网时手机连的是设备热点，那条链路没有外网，如果等到点「开始配网」才去取令牌，涂鸦会直接返回 `Network error please try it again`——这个报错与设备、与 Wi-Fi 密码都无关，纯粹是取令牌的时机不对。

因此桥接把取令牌拆成了独立的 `prepareActivatorToken`，并在原生层缓存令牌（8 分钟，涂鸦签发的有效期是 10 分钟）。令牌**不回传 Dart**：它是短时效的云端凭据，而联调页会把收到的一切写进可见日志。`pairWifiDevice` 优先复用缓存令牌，没有或已过期才回落到云端取——EZ 全程连在路由器上，走的就是这条回落路径，所以 EZ 不需要额外操作；AP 下手机已在设备热点上、云端不可达，令牌必须提前取好。配网成功后立即清空缓存，涂鸦令牌是一次性的。

AP 模式的正确顺序：

1. 手机还连在路由器上时，填好**路由器**的 Wi-Fi 名称与密码（不是热点的），模式选 AP；
2. 点「获取配网令牌」，日志出现成功行；
3. 去系统设置连上设备热点，Android 弹出「此 WLAN 无法访问互联网」时选择保持连接；
4. 回到联调页点「开始配网」。

超过 8 分钟没点「开始配网」就要重新取一次令牌。
- 调用日志：时间、结果、失败码与脱敏账号，可复制或清空。页面与日志只显示脱敏账号，不显示密码、验证码或密钥。

已登录时冷启动会直接进入 `AppShell`，因此「我的」页标题栏右侧同样有一个联调图标入口，不需要退出登录就能回到该页。

两个入口在 debug 与 profile 构建中始终可见；release 构建必须显式开启：

```bash
flutter build apk --release --split-per-abi --dart-define=TUYA_DEBUG_TOOLS=true --no-pub
```

未开启时入口隐藏，`/devtools/tuya` 也会回落到登录页。Mock 模式下该页会明确提示调用只命中 Mock 后端，不能作为真实链路结论。

## 6. 当前桥接边界

`android/app/src/main/kotlin/com/common/yikaltd/MainActivity.kt` 中的桥接不硬编码涂鸦回调接口名：先按方法名与参数个数解析目标方法，再用该方法声明的最后一个接口参数生成动态代理。因此 `logout`（`ILogoutCallback`）与 `cancelAccount`（`IResultCallback`）、`getOtaInfo`、`setOtaListener` 等签名不同的接口能共用同一套调用代码，SDK 升级改名也不会静默失效。Expansion SDK 7.8.0 的初始化声明为 `ThingOptimusSdk.init(Context)`；反射查找必须使用声明类型 `Context`，实际参数仍可传入 `Application`。

已接通：账号（验证码、登录、注册、找回密码、改昵称、退出、注销）、家庭查询与自动建家、AP/EZ 配网、设备列表、DP 下发、重命名、解绑、恢复出厂、OTA 查询与升级、**设备 DP 实时上报**。

iOS 桥接（`ios/Runner/AppDelegate.swift`）现在覆盖同一组方法名：账号、家庭、设备列表、配网（含 `scanWifi` 与 `prepareActivatorToken`）、DP 下发、重命名、解绑、恢复出厂、DP 实时上报、OTA 查询与升级。两端方法名、参数名和错误码保持一致，Dart 侧只有一套 Repository。

### 6.0 设备 DP 实时上报

设备自己上报的东西不走方法通道，走一条单向事件通道 `com.common.yikaltd/tuya_events`（`TuyaConfig.eventChannelName`）。两端用各自 SDK 现成的监听：

| 平台 | 入口 |
| --- | --- |
| Android | `ThingHomeSdk.newDeviceInstance(devId).registerDevListener(IDevListener)`，回调 `onDpUpdate` / `onStatusChanged` / `onNetworkStatusChanged` / `onRemoved` / `onDevInfoUpdate`。 |
| iOS | `ThingSmartDevice(deviceId:).delegate`，回调 `device(_:dpsUpdate:)` / `deviceInfoUpdate(_:)` / `deviceRemoved(_:)`。 |

监听在 `getDevices` 成功后按返回的设备 id 集合注册，配网成功后补一台，解绑、恢复出厂、退出登录和注销时释放；没有任何轮询。事件形状两端一致：

```text
deviceId : String     必有
dps      : Map?       本次变化的功能点，键是 DP id 字符串
online   : bool?      上下线，或手机网络变化
removed  : bool?      设备已从账号移除
device   : Map?       设备信息变化后的整份快照
```

Dart 侧 `MethodChannelTuyaRepository` 保留每台设备最近一次的原始 map，把增量合并进去后重新解码成 `SmartPlanterDevice`，通过 `TuyaRepository.deviceUpdates` 发出；`FlowerpotState` 订阅后替换设备并 `notifyListeners()`。因此 103–116、131–139、145 这些上报会自己刷新，不再依赖手动下拉；116 会用后端/本地已知英文标识符更新当前植物。合并是有状态的：只给某台设备推 DP、而这台设备本次会话从没出现在设备列表里时，事件会被丢弃，等下一次 `getDevices` 带回完整快照。

设备回执同样走这条通道：下发开关后设备把新值报回来，`FlowerpotState` 会用设备值刷新本地那份设置副本，所以在设备上按实体键改的设置也能反映到界面。

刷新范围有一处要知道：设备卡片和状态页的当前读数会自己变（`FlowerpotScope` 是 `InheritedNotifier`），但趋势图取的是 `historyFor` 返回的 `Future`，只在进入页面时求值一次——新到的历史包要重新进页面才会画出来。

传感器历史不再走云端统计服务：131–139 是设备自己上报的 raw 历史包，`getDevices` 读回 `dps` 时就地解码，`getHistory` 直接从这份快照取。原生侧的 `getStatistics` 分支因此不再被 Dart 调用，保留只是没必要为此改原生。

尚未接通，调用会返回明确错误码而不是假数据：

- `uploadAnimation` → `product_protocol_required`：APP 后端的图片列表、上传和删除已经接通代码链路，但动画同步到硬件仍需要 PID 对应的协议。表里的 142/143/144（下载图片、显示图片、取消显示）是设备侧链路，142 收 URL；后端上传返回 URL 后还要确认编码、大小限制与设备回执。
- `createShareLink` → `share_service_unavailable`：Android 侧的分享链接由业务拓展 SDK 提供，管理类包名需要在开通设备分享后核对；iOS Home SDK 只有按账号分享，没有生成链接的接口（见第 3 节）。

还未实现的能力：

- 温度、湿度、电量、PPFD、DLI 五条趋势曲线没有历史 DP：表里只有水仓水位、土壤湿度、光照各三个窗口。这几页在真实设备上显示「暂无历史数据」空态——不再用当前读数画一个点冒充趋势。要出曲线得在平台补 DP 或自建后端。
- **SDK 意义上的设备发现**。桥接里没有任何设备扫描接口，`TuyaRepository` 也没有对应契约。**产品确认设备只支持 2.4GHz Wi-Fi 配网，没有蓝牙配网**，因此这里不应该去实现 BLE 扫描：EZ/AP 配网本来就没有「SDK 扫描出一台设备再选」这一步。能被手机真实观测到的只有设备在 AP 模式下自己拉起的热点，配网三页现在就建立在这一条真实证据上（见 6.3）。

配网前的运行时权限只申请 Wi-Fi 相关项：API 33 以下要求 `ACCESS_FINE_LOCATION`，API 33 及以上要求 `NEARBY_WIFI_DEVICES`（同时申请但不强制 `ACCESS_FINE_LOCATION`）。不要再把 `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` 加进配网前置检查：设备没有蓝牙配网，而这两项被拒绝会让整个配网直接返回 `permission_denied`。Manifest 中仍保留蓝牙声明（涂鸦 SDK 自身可能合并同名权限），但 App 不会主动申请。

### 6.1 配网相关类名不要硬编码

`startActivator` 里的 `ActivatorBuilder` 和 `ActivatorModelEnum` **不再按全限定名 `Class.forName`**。涂鸦在 7.x 内部挪过这两个类的包名（曾出现过 `com.thingclips.smart.sdk.builder.ActivatorBuilder` 与 `com.thingclips.smart.home.sdk.builder.ActivatorBuilder` 两种写法），名字写错时只会抛一个光秃秃的 `ClassNotFoundException`，从错误码上完全看不出真正原因——而此时 `getActivatorInstance()` 和 `getActivatorToken()` 其实都已经成功了，问题只出在最后一步取类。

现在改成从方法签名反查类型，和 `invokeWithCallback` 取回调接口是同一套做法：

- Builder 类型 = 工厂方法的唯一参数类型；
- 模式枚举 = 该 Builder 上 `setActivatorModel(...)` 的参数类型，再按常量名匹配。

常量名同样被改过：**7.5.1 里是 `THING_AP` / `THING_EZ`（完整清单 `THING_AP, THING_EZ, THING_4G_GATEWAY, THING_STATIC_IP, THING_QR`），没有任何 `TY_*`**。`EZ_MODE_NAMES` / `AP_MODE_NAMES` 按「新名在前、旧名兜底」的顺序匹配，两代 SDK 都能用。

**工厂方法要按模式选**：`newMultiActivator` 是多设备配网，只实现了 EZ，喂给它一个 AP 的 Builder 会在 `start()` 时报 `Multi Config don't support the AP Mode`。所以 AP 只允许 `newActivator`（单设备），EZ 优先 `newMultiActivator`、缺失时回落到 `newActivator`。这个约束在涂鸦的 API 签名上完全看不出来，只能从运行时报错知道。

两处解析失败时抛出的异常都会把 SDK 实际提供的方法签名或枚举常量名列进消息里，联调页日志能直接看到，无需再翻 AAR。新增其它配网能力时沿用这个思路，不要再往桥接里塞全限定名。

### 6.2 界面上的占位数据

界面不再标注占位数据，判断某个值是否真实要回到源码：设备与传感器值来自 `TuyaRepository`（Mock 模式全部是模拟值，真实模式在 DP 缺失时回落到默认值）；配置 APP 后端并登录后，植物目录/详情与设备图片来自 REST，未配置时植物使用本地目录、设备图片使用 Mock/本地流程；帮助中心、协议正文、关于页版本号等仍是写死文案。真实链路验证以 SDK/HTTP 调试日志为准，不要以页面上显示的数字为准。

### 6.3 配网三页现在调的是真实接口

配网动线不再有模拟数据，三页调用的都是 5.3 里联调页验证过的同一组桥接方法：

| 页面 | 真实调用 | 说明 |
| --- | --- | --- |
| `DeviceSearchPage`（搜索设备） | `scanWifi` | 进页即扫描。扫到设备热点（`SmartLife-*`、`TY_*`、`YSplanter-*`）才自动进入选择页；扫不到、列表为空或扫描被拒绝都停在本页，显示原因、「重新扫描」和「设备已在配网状态，继续」。 |
| `DeviceSelectionPage`（选择设备） | `scanWifi` | 列出的就是扫到的设备热点，名称与信号格来自 `WifiNetwork.ssid` / `level`。选中的热点名会随 `PairingArguments.hotspotSsid` 传到下一页。没有热点时是空态加重新扫描，不再伪造 `YSplanter-01/02/03`。 |
| `PairingPage`（连接 Wi-Fi） | `scanWifi`、`prepareActivatorToken`、`pairWifiDevice` | 进页自动带入手机当前连接的 2.4G 网络名；「切换」弹窗列的是扫到的 2.4G 路由器（滤掉 5G 与设备热点）。AP 模式拆成两步：先取令牌，再连热点后开始配网。 |

几条必须知道的边界：

- **AP 两步是硬要求，不是交互偏好**。`getActivatorToken` 是云端调用，手机连上设备热点后就没有外网了。产品页因此和联调页一样先取令牌（按钮显示「下一步：连接设备热点」），令牌就绪后按钮才变成「开始配网」。令牌只存在原生层，Dart 侧只记录取回时间用于判断是否需要重取（7 分钟，短于原生缓存的 8 分钟）。配网成功后清空，涂鸦令牌一次性。
- **扫不到不等于没有设备**。iOS 的 `scanWifi` 只返回当前连接的 SSID，`networks` 恒为空；Android 9 起扫描受频率限制，定位关闭时返回 `location_disabled`。因此三页在列表为空时给的都是「无法列出」而不是「没有设备」，并且始终保留手动继续的入口——配网本身不依赖扫描结果。
- 「连接」按钮不会真的去连热点：Android/iOS 都不允许应用静默加入某个 Wi-Fi。它只是把选中的热点名带到下一页，由 AP 引导卡片告诉用户去系统设置连哪一个，并可点「检查连接」重新扫描确认。

## 7. 发布前检查

- Android 包名、签名 SHA-256、AppKey/AppSecret、安全 AAR 完全匹配。
- 使用 `apksigner verify` 核对所有待分发 APK 的签名有效且证书一致。
- iOS Bundle ID、AppKey/AppSecret、ThingSmartCryption 完全匹配。
- 关闭 release SDK debug 日志。
- 购买/构建正式版 SDK，补齐隐私清单和第三方 SDK 清单。
- 验证 AP 配网、本地网络权限、设备分享深链、OTA 中断恢复与账号数据区域。
