# Android 涂鸦接入配置复核与可运行化

> 文档类型：Historical Change Record
> 日期：2026-08-17
> 环境：远程 SSH 工作区（无 Flutter/Android/Java 工具链）
> 分支与起始版本：main / 157d8d8
> 范围：Android Gradle 配置、签名策略、涂鸦 SDK 初始化位置、Flutter 原生桥接
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

用户已在涂鸦开发者平台完成包名、SHA-256 与相关配置，要求复核当前仓库的接入配置是否完善，并把代码改到「拉到本地即可在模拟器上跑起来」的状态。本次不构建、不运行，只做配置审查与源码修改。

## 变更内容

- `android/app/build.gradle.kts`
  - 签名门禁从「任何 assemble/build 任务缺 `key.properties` 即失败」收敛为「只有 release 产物失败」。debug 与 profile 在缺少 `key.properties` 时回退到 Android 默认调试证书并打印提示，`flutter run` 不再被阻断。
  - 把安全 AAR 与 `local.properties` 中的涂鸦密钥提到 `android {}` 之外统一解析，配置阶段打印 SDK 是否链接、密钥是否缺失以及 ABI 限制。
  - 为 release 构建类型显式挂上 `proguard-rules.pro`。此前该文件从未被任何构建类型引用，一旦开启压缩，反射桥接依赖的 `-keep class com.thingclips.**` 不会生效。
- 新增 `android/app/src/main/kotlin/com/common/yikaltd/FlowerpotApplication.kt`
  - 按涂鸦要求把 `ThingHomeSdk.init` 与 `ThingOptimusSdk.init` 移到 `Application.onCreate`。
  - `ThingHomeSdk.init` 全进程只调用一次，避免 Flutter 热重启重复初始化。
  - 初始化前依次检查 SDK 是否编入、密钥是否存在、当前 ABI 是否受支持，失败只记录 `sdk_unavailable` / `credentials_missing` / `sdk_abi_unsupported` / `security_component_mismatch` 并让 App 正常启动。
  - 统一异常归类，含从 cause 链中识别嵌套的 `AEADBadTagException` 与 `UnsatisfiedLinkError`。
- `android/app/src/main/AndroidManifest.xml`：`android:name` 由 `${applicationName}` 改为 `.FlowerpotApplication`。
- `android/app/src/main/kotlin/com/common/yikaltd/MainActivity.kt`
  - 回调代理不再按接口名猜测：先按方法名与参数个数解析目标方法，再用该方法声明的最后一个接口参数生成代理。
  - 修复 `cancelAccount`：原实现固定使用 `ILogoutCallback`，而该方法要求 `IResultCallback`，方法解析必然抛 `NoSuchMethodException`。
  - 修复 `startFirmwareUpgrade`：7.x 的 `startOta()` 无参，进度与结果走 `setOtaListener`；原实现按带回调参数调用。
  - 桥接方法执行前统一检查初始化状态，失败返回记录的错误码。
  - `onError`/`onFailure` 参数个数因接口而异，改为从 String 参数中提取错误码与文案。
  - 代理显式处理 `equals`/`hashCode`/`toString`，避免 `toString` 返回 null。
  - 配网结束后统一停止 activator；`createShareInfo` 无可用管理类时返回 `share_service_unavailable` 而不是抛 `ClassNotFoundException`。
  - 修正 `deviceMap` 中 `getProductId` 的重复回退（改为 `getProductId` → `getPid`），并为家庭创建、配网、设备详情补齐空返回保护。
- 新增 `android/key.properties.example`。
- 更新 `docs/TUYA_SDK_SETUP.md`：签名策略、ABI 与模拟器要求、初始化位置、前置条件与错误码对照表、桥接已接通与未接通能力。
- 更新 `AI_CONTEXT.md` 第 6 节约束 3，补充 ABI 约束。
- 修正 `docs/TUYA_SDK_SETUP.md` 中「真实模式需要关闭静态预览」的过时说法：`StaticPreviewConfig.enabled` 只影响 Mock 后端是否预置演示设备，真实模式下 `TuyaRepository.create` 会忽略该参数；真正需要注意的是登录页「体验模式」按钮会把仓库切换成 `MockTuyaRepository`。

## 关键决策

- release 仍然硬失败、不静默降级为调试签名；只放开 debug/profile。涂鸦校验签名 SHA-256，UI 与 Mock 模式不需要正式证书，真实链路需要，二者用同一份 `key.properties` 控制。
- 涂鸦初始化保持「尽力而为」：宁可 App 正常启动、由 Flutter 侧收到明确错误码，也不在 `Application.onCreate` 崩溃。
- 回调接口从目标方法签名反推，而不是维护接口名列表。这同时修复了 `cancelAccount`，并降低 SDK 升级改名后静默失效的概率。
- 设备分享管理类名仍无法从本仓库确认，保留现有候选包名，但把失败路径改为明确错误码，不臆造 API。

## 外部操作

- 无。本次没有访问涂鸦平台，没有下载任何 SDK 或安全组件，没有读取或记录密钥。

## 验证结果

- 未执行任何构建、分析或测试：当前 SSH 环境没有 Flutter、Dart、Java 与 Android SDK（`which flutter dart java` 均无结果），且用户明确要求本次不运行。
- 所有结论来自源码、Gradle 配置、`AndroidManifest.xml`、已提交的涂鸦配置资源与 `2026-08-17-android-tuya-sdk-integration.md` 的实测记录。
- ABI 结论直接依据上一份记录中「Debug/Release APK 只包含 armeabi-v7a 与 arm64-v8a 安全算法库」的实测结果。

## 未完成项与风险

- 本次改动未经编译验证，需要在有工具链的环境先跑 `flutter run`（Mock）与 `flutter build apk --debug --dart-define=TUYA_ENABLED=true`。
- 上一次记录中的 `AEADBadTagException` 仍未解决。用户已重新配置平台 SHA-256，需要在同一个 SDK 应用下重新构建并下载 `security-algorithm.tar.gz`，与 AppKey/AppSecret/包名/证书保持同一份配置快照。
- `TuyaConfig.dp` 101–123 仍是占位映射。
- 设备 DP 实时上报未实现：当前只在 `getDevices` 时读取一次 `dps`。接入需要注册 `IDevListener` 并新增事件通道，同时扩展 `TuyaRepository` 契约。
- `getStatistics`、`uploadAnimation`、`createShareLink` 仍返回明确的未接通错误码。
- 改用自定义 `Application` 后，若后续引入依赖 `${applicationName}` 的插件，需要确认其不要求特定 Application 基类。

## 回滚或恢复

- 恢复 `AndroidManifest.xml` 的 `android:name="${applicationName}"` 并删除 `FlowerpotApplication.kt`，即可回到 Activity 内初始化。
- 回退 `android/app/build.gradle.kts` 即可恢复「所有构建类型强制正式证书」的签名门禁。
- 桥接改动集中在 `MainActivity.kt` 单文件，可整体回退。
- 未改动签名文件、密钥、安全组件与涂鸦平台配置。
