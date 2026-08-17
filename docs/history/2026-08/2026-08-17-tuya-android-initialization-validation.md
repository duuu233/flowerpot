# Android 涂鸦 SDK 初始化验证

> 文档类型：Historical Change Record
> 日期：2026-08-17
> 环境：本地 Windows / OPPO R11 Plus 夜神 Android 12 模拟器
> 分支与起始版本：main / 23233b5
> 范围：Android 涂鸦凭据验证、ARM ABI 安装、Expansion SDK 初始化桥接
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

涂鸦平台已补充 Android 证书 SHA-256，用户重新下载 SDK 与安全组件，并修正本机 `android/local.properties` 中写错的 AppSecret。本次目标是重新验证真实模式初始化，并处理验证过程中暴露的平台桥接问题。

## 变更内容

- 核对新下载的安全 AAR、Home SDK 依赖清单和 BizBundle 配置资源；它们与工程当前本地材料逐字节一致，因此没有重复替换。
- 将 `ThingOptimusSdk.init` 的反射参数类型从 `Application` 修正为 SDK 7.8.0 实际声明的 `Context`。
- 更新 Android 接入 Runbook，记录 x86_64 模拟器可能需要 arm64-only 构建并通过 `adb install --abi arm64-v8a` 显式安装。
- 更新当前 AI 上下文与 PRD 跟踪状态，区分“SDK 初始化已通过”和“真实业务链尚未联调”。

## 关键决策

- 不记录或输出 AppKey、AppSecret、签名资料和安全组件校验值；只验证凭据非空且合并后的 Manifest 与本地忽略配置一致。
- `Class.getMethod` 使用精确参数类型匹配。虽然 `Application` 是 `Context` 子类，但查找 `init(Application)` 无法命中声明为 `init(Context)` 的方法。
- 模拟器 ABI 列表包含 ARM 不代表通用 Flutter APK 会以 ARM 进程运行；本机实例必须在安装时显式指定 `arm64-v8a`。

## 外部操作

- 用户在涂鸦平台完成证书 SHA-256 配置并修正本机 AppSecret；本次 AI 操作未修改平台配置。
- 构建并安装真实模式 Debug APK，读取仅限应用初始化与原生加载错误的脱敏日志。
- 通过本地 Gradle 缓存中的 SDK 7.8.0 API JAR 只读确认 `ThingOptimusSdk.init(Context)` 方法签名。

## 验证结果

- `flutter build apk --debug --dart-define=TUYA_ENABLED=true --no-pub`：通过。
- 修正 AppSecret 后，原先的 `AEADBadTagException` 消失，证明安全配置解密已通过。
- 通用 APK 在当前模拟器中优先按 x86_64 运行，涂鸦原生库加载时报 `libc++_shared.so not found`。
- `flutter build apk --debug --target-platform android-arm64 --dart-define=TUYA_ENABLED=true --no-pub`：通过。
- 普通安装 arm64-only APK 时模拟器仍错误地按 x86_64 启动；使用 `adb install -r --abi arm64-v8a` 后应用稳定运行。
- 修正反射签名后，脱敏日志确认 `ThingHomeSdk.init` 与 `ThingOptimusSdk.init` 均成功返回，应用进程保持存活。

## 未完成项与风险

- 尚未使用真实账号验证登录、家庭创建、配网、设备列表、DP 下发、分享和 OTA。
- 当前模拟器的 ARM 转译依赖显式安装参数，普通 `flutter run` 不能代表真实模式可用；优先使用 arm64 模拟器或真机完成后续联调。
- `TuyaConfig.dp` 的 101–123 映射仍为占位，不能用于量产协议。
- iOS 密钥、安全组件、签名与真实链路仍未验证。

## 回滚或恢复

- 回退 `FlowerpotApplication.kt` 中 `Context` 参数类型及本次 Active 文档更新，可恢复修改前状态；这会重新引入 Expansion SDK 初始化的 `NoSuchMethodException`。
- 删除本地安全 AAR 可恢复为完全不链接真实 SDK 的 Mock/UI 构建；仅移除本地凭据时 SDK 仍会编入 APK，但初始化会安全地报告凭据缺失。这些本地材料均未提交。
