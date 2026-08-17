# Android 涂鸦 Release 签名构建验证

> 文档类型：Historical Change Record
> 日期：2026-08-17
> 环境：本地 Windows
> 分支与起始版本：main / ef20256
> 范围：Android Tuya 安全组件、本地签名配置与 Release APK
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

从仓库内受控但不提交的 `assets/Android_SDK` 与 `assets/AndroidKeys` 恢复本机 Android 涂鸦构建材料，生成真实 Repository 模式的签名 Release APK，并核对 APK 实际签名证书是否与本机公开证书及涂鸦平台登记值一致。

## 变更内容

- 将指定安全 AAR 复制到 `android/app/libs/security-algorithm.aar`，并通过文件哈希确认复制完整。
- 生成 Git 忽略的 `android/local.properties`、`android/key.properties` 与 `android/tuya-platform.properties`，由用户在本机填写秘密或受控值。
- 将 `assets/AndroidKeys/` 与本地平台指纹核对文件加入 Git 忽略规则，避免私钥和本机配置进入版本控制。
- 使用 `TUYA_ENABLED=true` 构建 `armeabi-v7a`、`arm64-v8a` 与 `x86_64` 三个分 ABI Release APK。

## 关键决策

- 不在源码、文档、命令输出或历史记录中保存 AppKey、AppSecret、证书密码、私钥内容或平台登记指纹原值。
- 通过被忽略的本地属性文件读取密码，调用签名工具时使用进程环境变量，避免把密码放进命令行参数。
- 区分 APK 文件 SHA-256 与 APK 签名证书 SHA-256；涂鸦平台校验的是后者。
- `x86_64` APK 虽可构建并正确签名，但涂鸦原生库不支持该 ABI，不作为真实配网分发包。

## 外部操作

- 用户在本机受控文件中填写 Tuya 凭据、签名密码和平台登记指纹；AI 未读取或记录其明文值。
- 本次未修改涂鸦开发者平台配置，也未向外部分发 APK。

## 验证结果

- `keytool -list`：现有 PKCS#12 签名容器成功解锁，私钥条目与公开证书可读取。
- `flutter pub get`：通过。
- `flutter build apk --release --split-per-abi --dart-define=TUYA_ENABLED=true --no-pub`：通过。
- 生成 `app-armeabi-v7a-release.apk`、`app-arm64-v8a-release.apk`、`app-x86_64-release.apk`。
- `apksigner verify --verbose --print-certs`：三个 APK 均签名有效，实际签名证书指纹均与涂鸦平台登记值及公开证书一致。
- 本次只验证了构建和签名；尚未在 ARM 真机上验证账号、家庭、Token、AP 配网和设备上线。

## 未完成项与风险

- 优先安装 `arm64-v8a` APK 完成真机真实账号与真实设备 AP 配网联调。
- 当前设备搜索、设备选择和 Wi-Fi 列表仍包含静态演示数据，正式配网体验尚需改造。
- 产品 DP 101–123 仍为占位，配网成功不代表设备控制契约已完成。

## 回滚或恢复

- 本机可移除复制后的安全 AAR、本地属性文件和 `build/` 产物，源材料仍保留在受控且被忽略的 `assets/` 目录。
- Git 忽略规则用于保护私钥和本地配置，通常应保留；若确需回退，只撤销对应忽略规则和本记录，不应把本地秘密加入版本控制。
