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

安全 AAR 存在时，Gradle 会自动启用 `thingsmart:7.5.1` 与 `thingsmart-expansion-sdk:7.8.0`，原生桥接会依次初始化 `ThingHomeSdk` 和可用的 `ThingOptimusSdk`。没有 AAR 时不下载 SDK，方便普通 UI 构建和测试。

项目 `minSdk` 为 24：满足当前 Flutter 图片选择插件要求，也高于涂鸦 Android SDK 的最低要求 23。

若启动时报 `security_component_mismatch` 或日志中出现 `AEADBadTagException`，表示安全组件无法解密当前应用配置。依次确认 AppKey、AppSecret、包名 `com.common.yikaltd`、APK 实际签名 SHA-256 与平台完全一致，然后在同一个 SDK 应用下重新构建并下载 `security-algorithm.tar.gz`。不要在工程任意目录额外放置旧版 `t_s.bmp`；安全图片已封装在新安全 AAR 内。

Debug、profile 与 release 构建统一使用正式证书，且不会回退到默认调试签名。请在 `android/key.properties` 配置正式证书（文件已忽略提交）：

```properties
storeFile=path/to/release.jks
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
storePassword=YOUR_STORE_PASSWORD
```

不要在 `android.defaultConfig` 中手动配置 `ndk.abiFilters`。Flutter Gradle 插件会根据构建参数管理 ABI；手动过滤会与 `--split-per-abi` 注入的拆分配置冲突。生成按 ABI 拆分、使用正式证书签名的 release APK：

```bash
flutter build apk --release --split-per-abi --no-pub
```

该命令只决定 Android release 构建和拆包方式，不会自动启用真实涂鸦链路。真实设备生产构建仍需按第 5 节启用 `TUYA_ENABLED`，关闭静态预览，并完成密钥、安全组件、DP 与真机验证。

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

## 5. 运行真实模式

```powershell
D:\Work\Flutter\flutter\bin\flutter.bat run --dart-define=TUYA_ENABLED=true
```

未传该开关时，App 使用本地体验数据，便于在密钥到位前验收产品流程。

## 6. 发布前检查

- Android 包名、签名 SHA-256、AppKey/AppSecret、安全 AAR 完全匹配。
- 使用 `apksigner verify` 核对所有待分发 APK 的签名有效且证书一致。
- iOS Bundle ID、AppKey/AppSecret、ThingSmartCryption 完全匹配。
- 关闭 release SDK debug 日志。
- 购买/构建正式版 SDK，补齐隐私清单和第三方 SDK 清单。
- 验证 AP 配网、本地网络权限、设备分享深链、OTA 中断恢复与账号数据区域。
