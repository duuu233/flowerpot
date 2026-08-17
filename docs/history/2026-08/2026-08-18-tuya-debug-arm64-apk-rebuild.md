# Android 涂鸦 SDK arm64 Debug APK 重新构建

> 文档类型：Historical Change Record
> 日期：2026-08-18
> 环境：Windows 本机构建机（Asia/Shanghai）
> 分支与起始版本：main / dd30484
> 范围：Android 本地构建、ABI 与签名验证；无业务源码或平台配置变更
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

上一轮构建目录仍存在，需要排除 Flutter 中间产物复用的影响，重新生成一个能直接进入涂鸦 SDK 联调页、调用真实原生仓库，并且不会在 x86_64 模拟器上选错 ABI 的 Android 调试包。

## 变更内容

- 执行 `flutter clean`，删除项目内的 `build/`、`.dart_tool/` 与 Flutter 生成文件；保留 Gradle 和 Pub 的依赖下载缓存。
- 重新执行 `flutter pub get`。
- 使用 `TUYA_ENABLED=true` 和 `TUYA_DEBUG_TOOLS=true` 构建 Debug APK；后者在 Debug 模式本来就默认开启，本次显式传入便于命令自说明。
- 首次仅使用 `--target-platform android-arm64` 的通用 APK 仍包含依赖 AAR 带入的其他 ABI JNI 文件，因此最终改用 `--split-per-abi` 生成 `app-arm64-v8a-debug.apk`。
- 修正 `docs/TUYA_SDK_SETUP.md` 中的 arm64 Debug 构建与安装命令。

## 关键决策

- 使用 Debug 而不是 Release：APK 带 `application-debuggable`，且 `FlowerpotApplication` 会让涂鸦 SDK 开启 Debug Mode。
- 使用按 ABI 拆分的 arm64 包：最终 APK 的 `native-code` 只有 `arm64-v8a`，不会让模拟器从包内选择 x86_64。
- 不清除全局依赖缓存：依赖缓存不保存本项目的 Dart define 或最终 APK，清除它只会触发重复下载；项目级中间产物已由 `flutter clean` 清除。
- 不修改或输出 AppKey、AppSecret、签名密码与证书内容；构建前只核对这些受控材料是否存在且配置完整。

## 外部操作

- 通过本机构建环境配置的 Flutter 镜像恢复依赖。
- 未修改涂鸦开发者平台、未安装 APK 到设备、未调用真实账号或设备接口。

## 验证结果

- 构建环境：Flutter 3.44.6、Dart 3.12.2。
- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub test/features/devtools/tuya_debug_page_test.dart`：4 个测试全部通过。
- 最终产物：`build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`，大小 104.87 MiB，SHA-256 为 `67153613F76A2AD0A2F60AA83990B36801F5000CB576F0882962330B66AB56CE`。
- `aapt dump badging`：包名 `com.common.yikaltd`、`application-debuggable`、minSdk 24、targetSdk 36、`native-code: 'arm64-v8a'`。
- APK 内存在 arm64 版 `libthing_security_algorithm.so`、`libthing_security.so`、`libthingmmkv.so` 与 `libThingSmartLink.so`。
- `apksigner verify --verbose`：通过 APK Signature Scheme v2 校验，签名者数量为 1。

## 下次构建命令

```bash
flutter clean
flutter pub get
flutter build apk --debug --split-per-abi --target-platform android-arm64 --dart-define=TUYA_ENABLED=true --dart-define=TUYA_DEBUG_TOOLS=true --no-pub
```

安装到需要显式选择 ARM ABI 的模拟器：

```bash
adb -s <device-serial> install -r --abi arm64-v8a build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
adb -s <device-serial> shell am start -n com.common.yikaltd/.MainActivity
adb -s <device-serial> logcat -s FlowerpotTuya
```

## 未完成项与风险

- 本次只完成静态、测试与 APK 结构验证，没有安装到模拟器或真机，因此 `ThingHomeSdk.init`、账号、家庭、设备列表和配网的真实返回仍需设备侧联调。
- 涂鸦 DP 101–123 仍是占位映射；即使 SDK 初始化与账号链路成功，也不能据此认定设备控制协议已完成验证。
- `build/` 是本机构建产物且不会进入 Git；跨环境复用必须在对应机器重新执行命令，或通过受控渠道传递 APK。

## 回滚或恢复

- APK 与构建中间产物均可通过 `flutter clean` 删除并重新生成。
- 若只回退本次文档修正，恢复 `docs/TUYA_SDK_SETUP.md` 的旧命令并删除本记录及两个索引条目即可；不涉及业务源码、平台密钥或签名材料。
