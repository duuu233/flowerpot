# 隐藏语言切换、iOS 包名改 com.common.yikaltdtext 与蒲公英用户包

> 文档类型：Historical Change Record
> 日期：2026-11-13；环境：远程 SSH 服务器
> 分支与起始版本：main / a4bab94

## 依据与范围

用户：
1. 隐藏花盆设置里的语种切换，默认中文。两处语言切换确认都隐藏。
2. 出一个没有日志的 iOS 包，在 Xcode 上打包，包名 `com.common.yikaltdtext`，发蒲公英。

## 改动

- 「我的 → 设置」去掉「语种设置」行。`FlowerpotState.initialize` 不再读本机 `languageCode` 偏好，App 界面固定简体中文；以前切到 English 的用户也回到中文。偏好值不删，恢复入口时改回读取即可。
- 花盆「其他设置」去掉「设备语言」行（DP153），同时去掉对应的选择框与下发。App 不主动给设备下发中文，设备屏幕保持当前语言，出厂默认是中文。割草机的语言页不在这次范围内，未动。
- iOS `PRODUCT_BUNDLE_IDENTIFIER`：Runner 由 `com.common.yikaltd` 改为 `com.common.yikaltdtext`（Debug / Release / Profile），RunnerTests 随之改为 `com.common.yikaltdtext.RunnerTests`。Android `applicationId` 仍为 `com.common.yikaltd`。原生通道名 `com.common.yikaltd/tuya` 只是通道标识，与包名无关，未改。

## iOS 无日志包打包步骤（Xcode，蒲公英 Ad Hoc）

前置条件（都要对上同一个 Bundle ID `com.common.yikaltdtext`）：

- Apple 开发者后台已注册该 App ID。Ad Hoc 描述文件要包含所有测试手机的 UDID：蒲公英 Ad Hoc 包只能装在描述文件里的设备上。企业账号可改用 In-House，不受 UDID 限制。
- 涂鸦平台 iOS 应用的 Bundle ID 填 `com.common.yikaltdtext`。从这个应用下载 `ios_core_sdk.tar.gz`，整理到 `ios/TuyaSDK/`（含 `ThingSmartCryption.podspec` 和 `Build/`）。`ios/Flutter/Tuya.xcconfig` 填该应用的 iOS AppKey / AppSecret。安全组件与 Bundle ID 不一致时，运行时报 `security_component_mismatch` 或无法登录涂鸦。这些文件不进 Git。

步骤（项目根目录，Mac 上执行）：

```bash
flutter pub get
# 生成带用户包参数的 Generated.xcconfig（只配置、不编译）；之后再用 flutter run / 不带参数的构建会把参数冲掉
flutter build ios --release --config-only --dart-define=APP_DEBUG_TOOLS=false --dart-define=API_BASE_URL=https://api.yikaltd.com
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

Xcode 中的操作：

1. Runner → Signing & Capabilities：选团队，确认 Bundle Identifier 为 `com.common.yikaltdtext`。
2. 设备选 Any iOS Device (arm64)，然后 Product → Archive。Archive 用 Release 配置，涂鸦 SDK 的 `debugMode` 只在 Debug 打开。
3. Organizer → Distribute App → Release Testing（Ad Hoc）→ 导出 ipa → 上传蒲公英。

也可以用一条命令出 ipa（同样需要签名可用）：

```bash
flutter build ipa --release --export-method ad-hoc --dart-define=APP_DEBUG_TOOLS=false --dart-define=API_BASE_URL=https://api.yikaltd.com
```

`APP_DEBUG_TOOLS=false` 的效果与 Android 用户包相同：不挂联调日志浮层、不记录交互日志、不写 OTA 调试日志文件、不显示诊断入口。业务上的消息通知「日志 / 提醒 / 告警」照常显示。版本号取 `pubspec.yaml`（当前 1.0.0+3）；蒲公英上要覆盖旧包时，构建号要递增，可以加 `--build-number=<更大的号>`。

## 验证

本机无 Flutter / Xcode，未编译、未运行测试、未打包、未真机。语言相关测试中没有断言这两行的用例。
