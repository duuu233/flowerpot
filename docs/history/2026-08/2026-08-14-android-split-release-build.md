# Android 按 ABI 拆分的 Release 构建

> 文档类型：Historical Change Record
> 日期：2026-08-14
> 环境：本地 Windows
> 分支与起始版本：main / b0c773f
> 范围：Android Gradle 发布配置与本地 APK 构建
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

执行 `flutter build apk --release --split-per-abi --no-pub`，生成按 ABI 拆分、使用项目正式证书签名的 Android release APK。

## 变更内容

- 删除 `android/app/build.gradle.kts` 中 `defaultConfig.ndk.abiFilters` 的应用层硬编码。
- 在 `docs/TUYA_SDK_SETUP.md` 记录按 ABI 拆分的 release 构建命令、ABI 配置边界与签名校验要求。
- 本地产生 ARM64、ARMv7 与 x86_64 三个 APK；`build/` 产物不纳入 Git。

## 关键决策

Flutter Gradle 插件会根据 `--split-per-abi` 管理 `android.splits.abi`，未拆分时也会自行限制 Flutter 支持的 ABI。应用层同时设置 `ndk.abiFilters` 会触发 Android Gradle 插件的互斥配置错误，因此删除重复过滤，而不改变签名、包名、SDK 依赖或业务代码。

本次按用户指定命令构建 release APK，没有传入 `TUYA_ENABLED=true`，也没有修改静态预览开关。产物是正式签名的 release 构建，但不据此认定真实涂鸦生产链路已经启用或验证。

## 外部操作

- 运行 Flutter Android release 拆分构建。
- 使用 Android SDK `apksigner` 校验三个 APK。
- 未上传、安装或分发 APK，未修改密钥、证书或本机秘密配置。

## 验证结果

- 初次构建复现 `ndk abiFilters` 与 `splits abi` 冲突。
- 删除应用层 ABI 过滤后，三个目标 APK 均生成，同时生成对应 SHA-1 文件。
- 三个 APK 均通过 `apksigner verify --verbose --print-certs`，使用 APK Signature Scheme v2，签名者数量为 1，证书一致。

## 未完成项与风险

- 未在真机安装或执行冒烟测试。
- 真实生产模式仍需关闭静态预览、传入 `TUYA_ENABLED=true`，并核对涂鸦密钥、安全组件、DP、证书平台登记与真实设备流程。
- `version` 当前仍由 `pubspec.yaml` 的 `1.0.0+1` 提供；正式分发前需按发布计划确认版本号与构建号。

## 回滚或恢复

删除本次本地 `build/` 产物即可撤销构建输出。若不再使用 Flutter 的 ABI 拆分机制，可按目标发布策略重新评估应用层 ABI 过滤；直接恢复原过滤会使 `--split-per-abi` 构建再次失败。
