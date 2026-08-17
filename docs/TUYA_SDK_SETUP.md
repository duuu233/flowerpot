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

- API 30 及以上的 x86_64 模拟器镜像（自带 ARM 转译，`Build.SUPPORTED_ABIS` 会包含 `arm64-v8a`）；
- arm64 模拟器镜像；
- 真机。

在不满足的镜像上，桥接返回 `sdk_abi_unsupported` 而不是崩溃。Mock 模式（不传 `TUYA_ENABLED`）不受 ABI 限制，任何模拟器都能运行。

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

`StaticPreviewConfig.enabled` 只影响 Mock 后端是否预置演示设备，不影响真实模式，真机联调前不需要改它。但登录页的「体验模式」按钮在任何构建下都会把仓库切换成 `MockTuyaRepository`；真实链路验证必须走正常登录，不要用该入口。

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

不传 `TUYA_ENABLED` 时使用 `MockTuyaRepository`，不加载任何涂鸦原生库，因此对模拟器 ABI、密钥、安全组件和签名都没有要求。缺少 `android/key.properties` 时 debug 会用默认调试证书继续构建，只在控制台打印一条提示。

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

## 6. 当前桥接边界

`android/app/src/main/kotlin/com/common/yikaltd/MainActivity.kt` 中的桥接不硬编码涂鸦回调接口名：先按方法名与参数个数解析目标方法，再用该方法声明的最后一个接口参数生成动态代理。因此 `logout`（`ILogoutCallback`）与 `cancelAccount`（`IResultCallback`）、`getOtaInfo`、`setOtaListener` 等签名不同的接口能共用同一套调用代码，SDK 升级改名也不会静默失效。

已接通：账号（验证码、登录、注册、找回密码、改昵称、退出、注销）、家庭查询与自动建家、AP/EZ 配网、设备列表、DP 下发、重命名、解绑、恢复出厂、OTA 查询与升级。

尚未接通，调用会返回明确错误码而不是假数据：

- `getStatistics` → `service_configuration_required`：报表历史数据需要在平台开通统计服务并接入统计 API。
- `uploadAnimation` → `product_protocol_required`：动画同步需要 PID 对应的文件传输协议。
- `createShareLink` → `share_service_unavailable`：分享链接由业务拓展 SDK 提供，管理类包名需要在开通设备分享后核对。

还未实现的能力：设备 DP 实时上报。当前只在 `getDevices` 时读取一次 `dps`，下发后 UI 不会收到设备主动推送的变化。接入时需要注册 `IDevListener` 并新增一条 Flutter 事件通道，同时扩展 `TuyaRepository` 契约。

## 7. 发布前检查

- Android 包名、签名 SHA-256、AppKey/AppSecret、安全 AAR 完全匹配。
- 使用 `apksigner verify` 核对所有待分发 APK 的签名有效且证书一致。
- iOS Bundle ID、AppKey/AppSecret、ThingSmartCryption 完全匹配。
- 关闭 release SDK debug 日志。
- 购买/构建正式版 SDK，补齐隐私清单和第三方 SDK 清单。
- 验证 AP 配网、本地网络权限、设备分享深链、OTA 中断恢复与账号数据区域。
