# Android 本地配置跨电脑交接

> 文档类型：Historical Change Record
> 日期：2026-08-18
> 环境：Windows 本机构建机（Asia/Shanghai）
> 分支与起始版本：main / dd30484
> 范围：Android 本机配置模板、涂鸦与签名材料交接说明
> 当前权威文档：`docs/TUYA_SDK_SETUP.md`

## 背景与目标

项目会在家庭与公司电脑之间切换。Android 真实涂鸦构建依赖多个被 Git 忽略的本地文件，逐项回忆容易漏配；但把 AppSecret、签名密码、JKS 或安全 AAR 明文提交会使受控材料永久进入 Git 历史。本次目标是让非敏感配置继续随 Git 同步，并把必须在新电脑输入的内容集中成一份可执行清单。

## 变更内容

- 新增 `android/local.properties.example`，只包含机器路径和涂鸦字段的占位符，并说明 Flutter 自动生成的字段不能跨电脑复制。
- 在 `docs/TUYA_SDK_SETUP.md` 增加“新开发电脑的一次性配置清单”：分别列出已进入 Git 的固定配置、禁止提交且必须本机恢复的材料、公司电脑配置顺序、无泄密检查和 arm64 Debug 构建命令。
- 保留现有忽略规则：`android/local.properties`、`android/key.properties`、`security-algorithm.aar`、JKS/keystore、原始 Android SDK 下载包仍不进入 Git。

## 关键决策

- 私有仓库也不保存明文秘密或签名材料；Git 历史、克隆副本和备份都会扩大泄露范围。
- 包名、SDK 版本、Gradle 逻辑、桥接源码与抽取后的非秘密运行资源继续由 Git 负责，换电脑不重复配置。
- AppKey/AppSecret、安全 AAR、JKS 与签名密码通过涂鸦平台、密码管理器或其他受控渠道恢复；Markdown 只记录字段名和目标路径，不记录真实值。
- 不提交机器相关的 SDK 绝对路径；模板允许每台电脑填写自己的 `sdk.dir` 与 `flutter.sdk`。

## 外部操作

无。未修改涂鸦平台，未复制或输出任何密钥、密码、证书、安全组件内容。

## 验证结果

- 通过 `git check-ignore -v` 确认 `android/local.properties`、`android/key.properties`、`android/app/libs/security-algorithm.aar` 与 JKS 仍被忽略。
- `android/local.properties.example` 不匹配忽略规则，可安全纳入 Git；文件只包含占位符。
- 当前已经跟踪的 Expansion SDK JSON、字体、主题和字符串资源无需在公司电脑再次复制。

## 未完成项与风险

- Git 不会传输真实秘密与二进制签名材料；公司电脑仍需从受控渠道取回一次，这是安全边界而不是遗漏。
- 若涂鸦平台重新生成安全组件、修改包名或更换签名证书，必须把 AppKey/AppSecret、安全 AAR 与平台注册的 SHA-256 作为同一批配置一起更新。
- 本次只增加模板和操作说明，没有变更构建逻辑，也没有再次生成 APK。

## 回滚或恢复

删除 `android/local.properties.example`，移除 `docs/TUYA_SDK_SETUP.md` 的新电脑清单及两个文档索引条目即可回退；本地秘密文件和构建逻辑不受影响。
