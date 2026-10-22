# 面向用户的 Android 构建

> 文档类型：Active Runbook
> 最后核验：2026-10-16
> 事实来源：DebugLogGate、Android 构建配置、当前 APK 与测试

## 两种构建

同一套源码支持联调包与用户包，不必手动修改源码开关。

| 参数 | 行为 |
| --- | --- |
| 不传 APP_DEBUG_TOOLS，或传 true | 沿用原联调功能，包括全局日志和页面诊断台；release 也可联调。 |
| --dart-define=APP_DEBUG_TOOLS=false | 构建时关闭调试界面、应用调试输出和诊断专用查询；运行时开关不能重新开启。 |

用户包关闭全局联调浮层与记录、割草计划底部解析/复制台、花盆消息监控的写死对照数据和额外查询、设备 DP 诊断入口、空列表账号/家庭诊断、配网日志与原始失败诊断、植物接口体检和接口原始响应调试框。计划编辑说明使用普通中文。

真实的消息通知“日志/提醒/告警”、设备控制、计划保存与回读、故障提示和升级判断继续运行。这里的“日志”是业务消息，不能因为关闭联调而删除。Android 自有日志和配网诊断事件遵循同一个构建参数；涂鸦 SDK release 调试模式关闭。第三方库和操作系统自身的错误输出不承诺完全消失。

## 前置配置

按 [TUYA_SDK_SETUP.md](TUYA_SDK_SETUP.md) 配置正式签名、安全组件和本机 AppKey/AppSecret；这些文件与密钥不能提交。Android release 缺签名配置会直接失败，不回退到调试证书。当前真实涂鸦仓库默认启用，原 TUYA_ENABLED、TUYA_DEBUG_TOOLS 参数已不控制当前应用；不要再用它们判断是否隐藏调试功能。业务默认 HTTPS 源站为 https://api.yikaltd.com。

## 打包命令

在项目根目录执行（PowerShell 或其它终端均可）：

```powershell
flutter pub get
flutter build apk --release --split-per-abi --target-platform=android-arm,android-arm64 --dart-define=APP_DEBUG_TOOLS=false --dart-define=API_BASE_URL=https://api.yikaltd.com --no-pub
```

当前版本为 1.0.0+3，输出：

- build/app/outputs/flutter-apk/app-arm64-v8a-release.apk：64 位 ARM 手机。
- build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk：32 位 ARM 手机。

不要发旧目录里残留的 x86_64 包：涂鸦安全组件只支持 ARM。Android 最低版本为 7.0（API 24）。之后发布时继续增加构建号，可改 pubspec.yaml 或加 --build-number=<更大的构建号>；ABI 拆包会在此基础上生成不同 Android versionCode，本次 ARM64 为 2003、ARMv7 为 1003。

保留原来的联调包，使用：

```powershell
flutter build apk --release --split-per-abi --target-platform=android-arm,android-arm64 --dart-define=APP_DEBUG_TOOLS=true --no-pub
```

仍可使用原来的 flutter run / debug 构建方式，省略新开关时联调能力默认打开。构建会覆盖同名输出 APK，需要同时保留两种包时先分别复制到自己的分发目录。

## 覆盖安装

用户包与联调包使用同一个 applicationId：com.common.yikaltd，可互相覆盖，不能同时安装成两个应用。覆盖需签名相同，且新包 versionCode 不低于已安装包；按同一 ABI 升级。当前配置在 key.properties 完整时使 debug/profile/release 使用同一正式证书。

本机旧 ARM64 release 为 1.0.0、versionCode 2002；本次为 2003，证书 SHA-256 核对记录在本次历史中。同名同签名覆盖不要求卸载或清数据，继续使用现有账号、设备及本机偏好。没有连接用户手机，因此不声称已对手机上的任意旧包验证覆盖；若旧包使用另一证书，需先找回同一签名材料；已装更高构建号则应继续提高新包构建号。

```powershell
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

反向从用户版覆盖回联调版也需满足相同的签名与版本规则，建议使用同号或更高号构建。

## 回归与交付边界

```powershell
flutter test --no-pub test/user_build_test.dart test/debug_log_gate_test.dart
flutter test --no-pub --dart-define=APP_DEBUG_TOOLS=false test/user_build_test.dart test/debug_log_gate_test.dart
```

两种参数分别验证调试入口、日志不采集、诊断查询不发起、真实消息和计划保存。用户包是关闭调试功能的正式签名 release 构建，仍需在目标手机上验收登录、设备控制、消息、计划与升级；本次不包括商店上架或其它部署。

## 构建目录清理

核验日期：2026-10-21。Android 根 Gradle 配置把 app 模块构建目录指向项目的 build/app。这里同时存放编译中间文件和最终输出，目录大小不等于 APK 大小。

在没有 flutter run、Flutter/Gradle 打包或相关编译任务运行时，可清理 build/app 下的 intermediates、generated、tmp、kotlin、kotlinToolingMetadata。这些目录由构建工具重建，不改变应用源码、依赖版本、签名和打包参数；首次重新打包需重新编译，耗时会增加，缓存也会再次增长。

保留 build/app/outputs，尤其是 flutter-apk 中的交付 APK、mapping 中的混淆映射，以及 native-debug-symbols 中的原生符号。outputs/apk 与 outputs/flutter-apk 可能保存同一安装包的两份输出；没有另存归档前不要一并删除。

不要为清理构建缓存而删除 android/key.properties、android/local.properties、签名证书、android/app/libs/security-algorithm.aar、平台资源或 SDK 安装目录。清理前核实目标绝对路径位于当前项目 build/app 内，目录不是符号链接或联接点，禁止对项目根目录使用递归删除。

需要保留现有安装包时不要直接执行 flutter clean：本项目完整 clean 的目标包含 build，最终输出也需先另存。日常只清上述中间目录即可，下一次仍使用本文原来的打包命令。

本次实测范围、占用和保留验证见 [构建缓存清理记录](history/2026-10/2026-10-21-android-build-cache-cleanup.md)。
