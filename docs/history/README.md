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

- [`2026-09/2026-09-11-pairing-stuck-fix-and-ble-discovery.md`](2026-09/2026-09-11-pairing-stuck-fix-and-ble-discovery.md)：**「输完 Wi-Fi 密码点下一步卡住」的修复**——`aef6ccd` 那次大删除把 `_pair()` 里的 `_pairingState = state` 与 `setState(() => _pairing = true)` 一起删了，进度页再也不出现、「取消配网」够不到、切后台还会把正在下发凭据的热点通道掐断；按 `223bdae^` 原样恢复并补回归断言。同轮按官方 4 步梳理配网并删掉多余代码（`pairDevice`、`PairingRequest.mode`、`PairingArguments.deviceName`、`_PairingHintCard`、三段悬空注释），另**新增 BLE 发现通道**（`getBleOperator().startLeScan` + `CombosFlagCapability.SCAN_WIFI` + `queryWifiListForDeviceScan`，与 Wi-Fi 扫描并行、不替换），反射目标用新工具 `tools/aar_class_dump.py` 解包逐个核对过。⚠️ BLE 全部未真机验证。
- [`2026-09/2026-09-10-toast-drop-source-prefix.md`](2026-09/2026-09-10-toast-drop-source-prefix.md)：toast 去掉 `接口-` / `涂鸦-` / `APP-` 来源前缀直接给内容；`_tagged` 改名 `_diagnostic` 只服务诊断行（`sessionDiagnostics` 与后端会话失效原因），来源信息仍在 `ActionResult.code` 里。
- [`2026-09/2026-09-10-ap-new-flow-implemented.md`](2026-09/2026-09-10-ap-new-flow-implemented.md)：配网整体切到涂鸦「热点配网新流程」——桥接新增 `apQueryDeviceWifi`/`apStartPairing`/`apStopPairing`，**连热点交给 SDK**，`WifiNetworkSpecifier` 与手动引导整套退出动线；「切换 Wi-Fi」改列设备自己扫到的网络。⚠️ 反射签名与固件版本（TuyaOS ≥ 3.6.1）均未真机验证。
- [`2026-09/2026-09-10-tuya-ap-new-flow-found.md`](2026-09/2026-09-10-tuya-ap-new-flow-found.md)：**找到官方「热点配网新流程」——SDK 自己会连热点**，不必再用 `WifiNetworkSpecifier`、也就没有系统授权框；`ThingApActivatorBuilder` / `IThingOptimizedActivator` / `queryDeviceConfigState` 等接口在 7.5.1 里已实测存在，无需升级 SDK。前置条件：设备固件 TuyaOS ≥ 3.6.1（待设备开发确认）。官方文档已存档到 `docs/reference/`。
- [`2026-09/2026-09-10-ap-only-and-system-consent-checklist.md`](2026-09/2026-09-10-ap-only-and-system-consent-checklist.md)：设备开发确认**只支持 AP（AP-cfg）、不支持 EZ/SmartConfig**，桥接里的 EZ 分支就此确认为死代码；并给出「昨天的包不需要授权」的排查清单——EZ 假设已排除，剩下「点按钮那一刻手机是不是已经连在设备热点上」与「系统记住了授权」两个待核实解释。仅文档，无代码改动。
- [`2026-09/2026-09-10-login-toast-only-and-toast-width.md`](2026-09/2026-09-10-login-toast-only-and-toast-width.md)：登录页去掉输入框下面那行校验提示（只留 toast，校验本身没松）；toast 宽度由写死 300 改成跟屏宽走，「请先阅读并同意用户协议与隐私政策」不再折行（原来留给文字只有 236，这句要 224，只差 12px）。
- [`2026-09/2026-09-10-pairing-flow-batch.md`](2026-09/2026-09-10-pairing-flow-batch.md)：配网动线七项——表单页键盘避让、配网期弹框收敛（含不再用通配前缀触发系统「查找设备」框）、第三步「连接云端」给 1–2 秒随机停留、失败页版式重排（小提示重叠 + 多余滚动条）、搜索页改内联列表并删除「选择设备」页、去掉「设备已在配网状态，继续」、启动页先只留背景图；另把 09-09 加的 `home_unresolved` 门禁降级为诊断（疑似「配网又不行了」的成因）。
- [`2026-09/2026-09-10-device-search-scan-throttle.md`](2026-09/2026-09-10-device-search-scan-throttle.md)：搜索不到设备——09-08 改成的「45 秒窗口每 2 秒重扫」把 Android「每 2 分钟 4 次 `startScan`」的配额在头 20 秒烧光，之后整窗口都在读上电之前的旧缓存。改成「2 次快扫 + 30 秒节奏 / 3 分钟窗口 / 出路全程可见」，桥接补 `throttled` 与 `ageMs`，被限流时明说而不是谎报「未发现设备」。
- [`2026-09/2026-09-10-auth-phone-format-feedback.md`](2026-09/2026-09-10-auth-phone-format-feedback.md)：手机号格式校验补上反馈——「获取验证码」不再按格式置灰（灰按钮点不动也不说话），改为照常可点、在发送前挡下并同时给 toast 与输入框下面那行常驻提示；登录/注册/重置提交也补上账号格式校验。
- [`2026-09/2026-09-10-animations-floating-action-bar.md`](2026-09/2026-09-10-animations-floating-action-bar.md)：定制动画的一排圆按钮从图库卡里搬到页面底部悬浮条——上传常驻、删除选中与取消选择有图才画；虚线上传位按 v2 设计稿改成只在空态出现。

- [`2026-09/2026-09-09-plant-dp-contract-v2.md`](2026-09/2026-09-09-plant-dp-contract-v2.md)：植物 DP 契约改版——116 变植物 id（-1 无植物 / 0..N 涂鸦标识 ID），162 变「弹不弹引导窗」两态且只上报；配套改设备列表门禁、详情页引导窗与无植物界面。

- [`2026-09/2026-09-09-code-review-cleanup.md`](2026-09/2026-09-09-code-review-cleanup.md)：代码审核轮次——移除调试台与体验模式、关闭 S1 明文回落、写请求不再重试、会话 revision 防迟到、搜索页销毁保护；ssh 端补静态自检与 Active 文档口径修复，S2/S3 仍未关闭。

- [`2026-09/2026-09-09-backend-session-expiry.md`](2026-09/2026-09-09-backend-session-expiry.md)：「用一个小时就掉登录」——后端 401/406 以前会 `_clearLocalSession()` 把涂鸦会话一起清掉，改为只清后端会话并留下失效原因与接口日志。

- [`2026-09/2026-09-09-verification-code-phone-format.md`](2026-09/2026-09-09-verification-code-phone-format.md)：发验证码前校验手机号格式——输入框只收 11 位数字，号码不合法时「获取验证码」禁用，三页都补了发送前的兜底校验。

- [`2026-09/2026-09-09-home-pinned-and-pairing-preflight.md`](2026-09/2026-09-09-home-pinned-and-pairing-preflight.md)：家庭 id 按涂鸦 uid 记在本地、每次会话开始钉给原生；配网前先确认家庭再取令牌并加遮罩 loading；空家庭列表在热点上不建家、正常网络下先重查一次。

- [`2026-09/2026-09-09-ota-version-pair.md`](2026-09/2026-09-09-ota-version-pair.md)：OTA 弹窗两个版本号都不对——不是进度弹层改坏的，Android 的 `firmwareVersion` 一直取的是协议版本 `pv`，且两行版本号来源不同；改取 `verSw` 并让 `checkFirmware` 成对返回同一条 OTA 记录的当前/新版本。

- [`2026-09/2026-09-09-relogin-device-list-empty.md`](2026-09/2026-09-09-relogin-device-list-empty.md)：重新登录读不到已绑定设备——设备列表拉取失败不再被吞成「暂无设备」（新增 `deviceLoadError` 与错误态重试），两端桥接的家庭选择从「取第一个」改成稳定规则。

- [`2026-09/2026-09-09-home-plant-image-from-backend.md`](2026-09/2026-09-09-home-plant-image-from-backend.md)：已绑定设备首页正中的图改取后台给该植物配的 `plantImg`，为空或加载失败才回落本地静态图；植物详情页本来就是这个口径。

- [`2026-09/2026-09-09-animation-tips-illustration-clip.md`](2026-09/2026-09-09-animation-tips-illustration-clip.md)：定制动画「提示」卡右下角背景图被 Stack 默认裁剪切掉下沿，改为卡片零内边距 + 文案自带 padding，图按设计稿右边出血、底部齐平。

- [`2026-09/2026-09-09-pairing-ssid-and-standby-inline.md`](2026-09/2026-09-09-pairing-ssid-and-standby-inline.md)：配网页 Wi-Fi 名称改为进页面强制重扫 + 回到前台刷新（不覆盖用户输入），休眠模式由二级页面改为「行为」页内第三张卡。

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
