# 本地操作更新记录

> 文档类型：历史记录规范与索引
> 状态：Active
> 最后核验：2026-08-25
> 事实来源：`AGENTS.md` 与项目文档治理约定

本目录补充 Git 提交，记录集中修改的背景、外部操作、验证和未完成项，但不替代源码、提交历史或 Active 文档。文件使用 `YYYY-MM/YYYY-MM-DD-topic.md`，任务完成后冻结。

## 模板

```markdown
# 主题

> 文档类型：Historical Change Record
> 日期：YYYY-MM-DD
> 环境：办公室 / 家庭 / SSH / 其他
> 分支与起始版本：branch / short-sha
> 范围：模块或仓库
> 当前权威文档：相关 Active 文档

## 背景与目标
## 变更内容
## 关键决策
## 外部操作
## 验证结果
## 未完成项与风险
## 回滚或恢复
```

只写实际完成的动作与验证。跨项目同步还要写上游来源、新契约、已同步内容、有意差异和未同步事项。禁止记录任何密钥、Token、签名材料、真实 Wi-Fi 信息、用户数据或完整环境文件。

## 索引

- [`2026-09/2026-09-08-settings-profile-and-update-batch.md`](2026-09/2026-09-08-settings-profile-and-update-batch.md)：设置/我的/关于十项——分享隐藏、帮助中心搬到设备设置、OTA 进度弹层、App 强制/提示升级链路、昵称与头像修复、列表行高下划线、养护建议改本地中英文案。

- [`2026-09/2026-09-08-i18n-scaffold-and-device-settings-batch.md`](2026-09/2026-09-08-i18n-scaffold-and-device-settings-batch.md)：落地可扩展的多语言框架（简中 + 英文），并完成首页顶栏设备名、自动检测植物独立页、其他设置清理、纪念日校验与样式、休眠模式（DP 151/152）七项。

- [`2026-09/2026-09-08-home-care-advice-carousel.md`](2026-09/2026-09-08-home-care-advice-carousel.md)：首页「今日养护」改为轮播四条状态（107/108/113/115）的养护建议，5 秒一条，并给这批状态文案补中英双语表。

- [`2026-09/2026-09-08-gallery-device-id-and-pairing-cleanup.md`](2026-09/2026-09-08-gallery-device-id-and-pairing-cleanup.md)：设备图库改按涂鸦 `deviceId` 调 `getUserProductImgList`（删掉换 `userProductId` 的前置链路），并清理配网搜索/选择页文案、加 45 秒搜索窗口、修首页指标卡对齐。

- [`2026-09/2026-09-05-release-readiness-review.md`](2026-09/2026-09-05-release-readiness-review.md)：核对客户端安全、会话竞态、配网取消、测试与双端发布准备度，记录性能建议及未验证边界。

- [`2026-08/2026-08-12-ai-context-codegraph-maintenance.md`](2026-08/2026-08-12-ai-context-codegraph-maintenance.md)：建立项目专属 AI 上下文、文档入口与 CodeGraph/历史记录规则。
- [`2026-08/2026-08-12-ui-reference-reaudit-continuation.md`](2026-08/2026-08-12-ui-reference-reaudit-continuation.md)：续作 UI 参考图复核，统一普通页面背景并清理品牌与选中态的复杂手绘图形。
- [`2026-08/2026-08-13-ui-runtime-visual-alignment.md`](2026-08/2026-08-13-ui-runtime-visual-alignment.md)：在 Android 12 模拟器中复核当前构建，校准主要页面位置、状态摘要卡与资源失败占位。
- [`2026-08/2026-08-14-android-split-release-build.md`](2026-08/2026-08-14-android-split-release-build.md)：解除 Flutter ABI 拆分与应用层 ABI 过滤冲突，生成并校验三个 release APK。
- [`2026-08/2026-08-15-demo-navigation-and-app-icons.md`](2026-08/2026-08-15-demo-navigation-and-app-icons.md)：为 UI 演示改造导航（底部菜单、去目录、配网顺序、设备与植物动线），并生成 iOS/Android 全套应用图标。
- [`2026-08/2026-08-17-android-tuya-sdk-integration.md`](2026-08/2026-08-17-android-tuya-sdk-integration.md)：接入 Android Home SDK 7.5.1、Expansion SDK 7.8.0 与安全组件，记录真实模式初始化阻塞及无密钥环境的条件构建。
- [`2026-08/2026-08-17-tuya-android-runnable-config.md`](2026-08/2026-08-17-tuya-android-runnable-config.md)：复核 Android 涂鸦接入配置，放开 debug 签名门禁、把 SDK 初始化移入 Application，并修复桥接回调解析与 OTA、注销调用。
- [`2026-08/2026-08-17-tuya-android-initialization-validation.md`](2026-08/2026-08-17-tuya-android-initialization-validation.md)：修正本地凭据后验证安全组件解密，修复 Expansion SDK 初始化反射签名，并记录 x86_64 模拟器显式 arm64 安装要求。
- [`2026-08/2026-08-17-tuya-android-release-signing-validation.md`](2026-08/2026-08-17-tuya-android-release-signing-validation.md)：恢复本机受控签名材料，构建真实 Tuya 分 ABI Release APK，并核对 APK 实际签名证书与平台登记值一致。
- [`2026-08/2026-08-17-tuya-sdk-debug-console.md`](2026-08/2026-08-17-tuya-sdk-debug-console.md)：在登录页增加涂鸦 SDK 联调入口，直接调用注册与登录并暴露原始失败码，为配网联调准备起点。
- [`2026-08/2026-08-18-tuya-debug-arm64-apk-rebuild.md`](2026-08/2026-08-18-tuya-debug-arm64-apk-rebuild.md)：清理 Flutter 构建产物后重新生成真实涂鸦 arm64 Debug APK，并验证 ABI、签名与 SDK 联调页。
- [`2026-08/2026-08-18-android-local-config-handoff.md`](2026-08/2026-08-18-android-local-config-handoff.md)：区分可进入 Git 的 Android 固定配置与必须本机输入的涂鸦、签名材料，并补充新电脑配置清单和模板。
- [`2026-08/2026-08-18-mock-data-markers.md`](2026-08/2026-08-18-mock-data-markers.md)：核查配网动线只有 Wi-Fi 一步是真实调用，清掉预填的假 Wi-Fi 凭据与配网前置的蓝牙权限，透传配网失败码，并收敛登录页入口。
- [`2026-08/2026-08-18-demo-flow-polish.md`](2026-08/2026-08-18-demo-flow-polish.md)：统一植物目录并接入植物图片，去掉底部 Tab 导航改为头像进入「我的」，并补齐演示数据。
- [`2026-08/2026-08-20-dp-live-updates-and-ios-bridge.md`](2026-08/2026-08-20-dp-live-updates-and-ios-bridge.md)：接入设备 DP 实时上报（Android/iOS 监听 + 事件通道）、报表空态、温标与时间格式跟随、恢复出厂下发 141，并补齐 iOS 桥接与安全组件接入。
- [`2026-08/2026-08-25-app-backend-plant-dp116-calibration.md`](2026-08/2026-08-25-app-backend-plant-dp116-calibration.md)：接入 APP 后端国内账号、用户设备、植物与设备图片，并落实 DP 116 双向同步和水位校准 0–3/取消 5 契约。
- [`2026-08/2026-08-26-pairing-real-sdk-flow.md`](2026-08/2026-08-26-pairing-real-sdk-flow.md)：把联调页验证过的 `scanWifi`、`prepareActivatorToken`、`pairWifiDevice` 接进配网三页，去掉搜索/选择/Wi-Fi 切换里的模拟数据，并把 AP 拆成取令牌与开始配网两步。
- [`2026-09/2026-09-03-pairing-resource-release.md`](2026-09/2026-09-03-pairing-resource-release.md)：复核一键 AP 配网链路，补齐失败/退出/超时时的热点连接与网络绑定释放、`cancelPairing`、令牌复用与 iOS/Android 9 的手动回落路径，并修正过期的测试与文档。
- [`2026-09/2026-09-03-verify-code-login-auto-register.md`](2026-09/2026-09-03-verify-code-login-auto-register.md)：定位「接口-403 邮箱不存在」为手机号未注册，把手机验证码登录补成登录注册一体（同一条验证码补注册），并区分「验证码错误」与「账号不存在」。
- [`2026-09/2026-09-03-pairing-device-discovery-from-raw-scan.md`](2026-09/2026-09-03-pairing-device-discovery-from-raw-scan.md)：把联调页「看到什么就列什么」的扫描逻辑搬进搜索与选择页，放宽热点前缀识别并让 Android `scanWifi` 等一轮新扫描结果。
- [`2026-09/2026-09-04-dialogs-dp-09-03-v2-pages.md`](2026-09/2026-09-04-dialogs-dp-09-03-v2-pages.md)：统一全项目弹窗样式，并入 09-03 功能点表的 151–160，落地纪念日/图库管理/配网进度/时段编辑等 v2 页面并新增 LED 设置页。
- [`2026-09/2026-09-07-device-entry-plant-confirm.md`](2026-09/2026-09-07-device-entry-plant-confirm.md)：并入 09-07 功能点表的 161/162 与占位的 163，落地设备详情页入口的「离线拦截 → 无植物直接添加 → DP 162 植物确认握手」，以及 116+161 同批下发和设置页的自动检测植物开关。
