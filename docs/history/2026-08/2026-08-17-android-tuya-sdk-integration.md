# Android 涂鸦 SDK 接入

> 文档类型：Historical Change Record
> 日期：2026-08-17
> 环境：本地 Windows 开发环境
> 分支与起始版本：main / 157d8d8
> 范围：Android Smart Life App SDK、本地安全组件、Flutter 原生桥接
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

用户从涂鸦开发者平台下载 Android SDK 与应用专属安全组件，目标是在保持无密钥环境仍可执行 Mock/UI 构建的前提下，接入 Android 真实 Smart Life App SDK。

## 变更内容

- 从用户提供的安全组件包中提取 AAR，并以本地忽略文件 `android/app/libs/security-algorithm.aar` 接入。
- 按下载包依赖清单接入 Home SDK 7.5.1，并独立接入 Expansion SDK 7.8.0。
- 按涂鸦业务拓展 SDK 要求补齐注解依赖排除与原生库冲突处理。
- 原生桥接在初始化 `ThingHomeSdk` 后初始化可用的 `ThingOptimusSdk`。
- 将下载包的完整 Android `assets/` 与默认 `res/values/strings.xml` 合并到应用主资源目录，补齐 Expansion/BizBundle 服务化配置。
- 为安全组件解密失败增加 `security_component_mismatch` 错误映射和不含敏感信息的初始化日志。
- 为 Release R8 增加当前未启用的 Flutter 动态模块、Matter JSON 与 Hilt 编译元数据精确告警规则。
- 忽略原始下载目录 `assets/Android_SDK/`，避免应用专属材料进入 Git。
- 更新 Android 接入 Runbook，明确安全组件、SDK 配置资源、Flutter UI 与 Android UI BizBundle 的边界。

## 关键决策

- 下载包根目录 `7.8.0` 是打包目录版本，Home SDK 的实际依赖契约以包内 `thingsmart_home_sdk/dependencies.txt` 指定的 7.5.1 为准；Expansion SDK 继续使用其独立的 7.8.0 版本。
- Gradle `dependencyInsight` 已确认 Expansion SDK 没有把 `com.thingclips.smart:thingsmart` 从 7.5.1 覆盖为其他版本。
- 下载包 README 将 `assets/` 与 `res/` 标为业务包必选资源；当前仍使用 Flutter 自有 UI，因此保留服务配置和默认字符串，不引入可选的 Android UI 多语言目录。
- 安全 AAR、AppKey/AppSecret、签名文件及原始下载包均保持本地，不进入源码或文档。
- 保留“安全 AAR 存在才启用涂鸦 Maven 依赖”的条件构建，确保其他开发环境在未配置涂鸦材料时仍可构建 Mock/UI 版本。

## 外部操作

- 输入材料来自用户已下载的涂鸦 Android SDK 资料包；本次未修改涂鸦平台配置。
- 构建期间解析了涂鸦 Maven 仓库中的 Home SDK 7.5.1 与 Expansion SDK 7.8.0 依赖。
- 使用 `TUYA_ENABLED=true` 将 Debug APK 安装到本地 OPPO R11 Plus 模拟器，并读取了仅限应用进程的脱敏启动日志。
- 尝试连接用户已登录的浏览器以只做配置一致性比对，但当前没有可用的浏览器控制实例；未读取浏览器存储，也未修改涂鸦平台配置。

## 验证结果

- `flutter build apk --debug --no-pub`：通过。
- `flutter build apk --debug --dart-define=TUYA_ENABLED=true --no-pub`：通过。
- Home 7.5.1 + Expansion 7.8.0 组合的 `debugRuntimeClasspath` 解析通过，最终 Home SDK 保持 7.5.1。
- `flutter build apk --release --dart-define=TUYA_ENABLED=true --no-pub`：通过，产物约 88.4 MB。
- 首次完整复制下载包多语言资源时，Release Lint 因 `values-tr` 中 `test_biz_scene_name` 缺少默认语言定义而失败；移除仅供 Android UI 使用的可选 `values-*` 目录、保留默认字符串后通过。被移除资源仍可从原始下载包恢复。
- `apksigner verify --verbose --print-certs`：通过，使用 APK Signature Scheme v2，证书 SHA-256 与平台登记指纹一致。
- 生成的 Debug APK 包含 `armeabi-v7a` 与 `arm64-v8a` 的应用专属安全算法库。
- 生成的 Release APK 同样包含两种 ABI 的安全算法库，且 R8 后仍保留 `ThingHomeSdk` 与 `ThingOptimusSdk`。
- 安全 AAR 从输入包到目标目录的字节数与 SHA-256 校验一致；校验值未记录。
- `dart analyze lib test`：通过，无问题。
- `test/tuya_config_test.dart` 与 `test/features/home/home_scene_test.dart`：4 项通过。
- 全量 Widget 测试存在 1 项与本次原生接入无关的既有失败：`test/widget_test.dart` 在进入搜索页后调用 `pumpAndSettle`，已跨过页面自身 2 秒自动跳转定时器，随后仍断言搜索页文案；单独复跑可稳定复现。

## 未完成项与风险

- 当前本机 AppKey/AppSecret 已配置且格式检查正常，具体值未输出或记录。
- 真实模式 APK 已成功安装并启动，但 `ThingHomeSdk.init` 抛出 `AEADBadTagException`。APK 内安全图片、算法配置和业务配置均与下载包逐字节一致，包名、APK 签名和本地密钥格式也已核对；剩余高概率原因是平台中的 AppKey/AppSecret/包名/证书与该安全 AAR 不属于同一配置快照，需要在平台复核后重新构建并下载安全组件。
- 在安全组件初始化通过前，账号、家庭、配网、设备控制、分享和 OTA 不能视为已联调。
- `TuyaConfig.dp` 中 101–123 仍为占位映射，不能作为量产设备协议发布。
- 业务拓展 SDK 的设备分享接口仍需在平台能力开通和真实账号环境中核验。
- 全量 Widget 测试中的既有配网流程时序断言需要在独立 UI 测试任务中修正。

## 回滚或恢复

- 删除本地 `android/app/libs/security-algorithm.aar` 后，Gradle 会恢复为不解析涂鸦 SDK 的 Mock/UI 构建。
- 回退 Gradle、原生桥接、Android SDK 配置资源、`.gitignore` 与 Runbook 变更即可恢复接入前源码状态。
- 不需要删除或变更签名文件；本次没有修改其内容。
