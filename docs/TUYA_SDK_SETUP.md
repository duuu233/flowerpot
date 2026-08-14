# 涂鸦 Smart Life App SDK 配置

当前桥接按 Android `thingsmart:7.5.6` 与 iOS 7.5.x 结构准备。涂鸦应用的包名必须与本项目 `com.common.yikaltd` 一致；若要更换包名，应在创建 SDK App 和下载安全组件前完成。

## 1. 开发者平台

1. 创建“智能家居 / Smart Life App SDK”应用。
2. Android 包名填写 `com.common.yikaltd`，配置调试与发布证书 SHA-256。
3. iOS Bundle ID 填写 `com.common.yikaltd`。
4. 选择 Home SDK、业务拓展 SDK、设备配网、设备管理、设备分享、数据统计和 OTA 能力。
5. 开发阶段可用开发版；上架前需要按涂鸦政策构建正式版安全组件。

## 2. Android

把平台下载资料包中的文件放到：

```text
android/app/libs/security-algorithm.aar
```

在 `android/local.properties` 追加（该文件不提交）：

```properties
tuya.appKey=YOUR_ANDROID_APP_KEY
tuya.appSecret=YOUR_ANDROID_APP_SECRET
```

安全 AAR 存在时，Gradle 会自动启用 `thingsmart:7.5.6` 与 `thingsmart-expansion-sdk:7.5.0`。没有 AAR 时不下载 SDK，方便普通 UI 构建和测试。

项目 `minSdk` 为 24：满足当前 Flutter 图片选择插件要求，也高于涂鸦 SDK 7.5.x 的最低要求 23。

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
