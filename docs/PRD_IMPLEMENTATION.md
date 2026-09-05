# 智能花盆 1.0 PRD 落地清单

来源：`智能花盆1.0开发方案.docx`。

2026-09-05：本表的“已实现”表示代码接入，不代表已通过真机或发布验收。当前静态分析、测试及发布阻塞见 [`RELEASE_READINESS_REVIEW.md`](RELEASE_READINESS_REVIEW.md)。

## App 已实现

| 一级模块 | PRD 内容 | 实现位置 |
| --- | --- | --- |
| 账号 | 国内手机号短信、验证码/密码登录与注册已接 APP 后端，并用返回的涂鸦映射凭据建立设备会话；验证码登录是登录注册一体的，手机号没有后端账号时用同一条验证码补注册；海外邮箱、找回/修改密码、退出、注销、头像和用户名保留原链路 | `core/backend`、`features/auth`、`features/profile`、`state.dart` |
| 首页 | 已配网设备列表、在线/信号/电量/充电、添加和删除设备 | `features/home`、`features/devices` |
| 配网 | 2.4 GHz Wi-Fi、Token、创建默认家庭；搜索/选择页按 `scanWifi` 列出设备热点，Wi-Fi 页只有 AP 一种方式、一次点击串完取令牌 → App 连热点 → 配网，平台不能连热点时回落手动引导；失败、退出页面、超时都释放热点与网络绑定并可取消 | `device_search_page.dart`、`device_selection_page.dart`、`pairing_page.dart`、`state.dart`、原生 Tuya bridge |
| 首页与状态详情 | 植物、陪伴天数、天气、水位、土壤、光照/PPFD/DLI、温度、湿度、电池 | `features/home`、`features/devices/presentation/*_status_page.dart`、`reports_page.dart` |
| 报表 | 水位/土壤湿度/光照日周月来自设备上报的 raw 历史包；温度、湿度、电池、PPFD、DLI 没有历史功能点，真机上是空态 | `reports_page.dart` |
| 设备实时性 | DP 上报、上下线、远端解绑由原生监听推送，页面自动刷新 | `tuya_repository.dart`、`state.dart`、两端桥接 |
| 设备图片 | APP 后端图片列表、上传、刷新、删除；硬件 142/143/144 显示协议仍待联调 | `core/backend`、`animations_page.dart` |
| 植物 | 按设备产品加载后台植物列表与详情，绑定/替换用户植物；绑定成功后把后台 `tuYaRemark` 下发到 DP 116，DP 116 上报反向更新当前植物 | `core/backend`、`plant_picker_page.dart`、`plant_detail_page.dart`、`state.dart` |
| 设备设置 | 名称、植物、硬件信息、OTA、分享/解绑/恢复出厂 | `device_settings_page.dart` |
| 感知设置 | 自动亮度、声音/触摸开关与灵敏度、振动 | `device_settings_page.dart` |
| 行为 | 中午小憩、夜间睡眠时间段和开关 | `device_settings_page.dart` |
| 本地化 | 温标与 12/24 小时既下发设备，App 自身展示也跟随（`DeviceControlSettings` 的格式化入口） | `device_other_settings_page.dart`、`tuya_models.dart` |
| 维护 | 水位校准按 `step0`→`step3` 逐步下发、取消发 `step5`（不发 `step4`）；修复系统文件、重新配网 | `device_settings_page.dart`、`water_level_calibration_dialog.dart` |
| 我的 | 中英文、消息开关、App 升级、帮助、隐私、协议、关于 | `features/profile` |

## 需要平台参数后联调

- Android 本机已完成 AppKey、AppSecret、包名、证书 SHA-256、安全 AAR 与 Home/Expansion SDK 初始化验证；账号、家庭、配网和设备链仍需真机与真实账号联调。秘密与安全组件不入库，其他开发环境必须独立配置。联调起点是登录页的「涂鸦 SDK 联调」入口（见 `TUYA_SDK_SETUP.md` 5.3），它直接调用注册、登录、会话与设备列表并显示原始失败码。
- 设备只支持 2.4GHz Wi-Fi 配网，没有蓝牙配网，因此不存在 SDK 意义上的「扫描并选择设备」。搜索页与选择页已改成基于 `scanWifi` 的「确认设备已进入配网状态」引导：扫到设备热点就列出来，扫不到或平台不支持枚举（iOS）时给出原因并保留手动继续入口，没有实现设备发现。产品页只有 AP 一种方式（实测唯一稳定配上的方式；EZ 保留在桥接层不暴露）：Android 10 起由 App 发起热点连接，系统弹框确认即可；iOS 需要 Hotspot Configuration entitlement，未配置时和 Android 9 及以下一样回落到「去系统设置连热点后再点一次」的手动路径。设备没有蓝牙，所以不存在 Wi-Fi+BLE 双模。真机仍需验证热点识别前缀是否覆盖量产 SSID，以及失败释放与取消在真机上的表现。
- iOS 安全组件已放入 `ios/TuyaSDK/`，Podfile 跟随其 SDK 线固定 `ThingSmartHomeKit ~> 7.8.0`；AppKey、AppSecret、Bundle ID、签名仍需在 Xcode 侧配置，且 iOS 全部改动尚未编译或真机验证。iOS 没有 Wi-Fi 扫描 API，分享只有按账号分享（见 `TUYA_SDK_SETUP.md` 第 3 节）。
- 除已确认的 116 外，产品 PID 与 101–115、117–123 DP 的最终对应关系、数据缩放倍率和枚举定义。
- 涂鸦设备数据统计服务的开通范围与统计 API。
- 设备图片/动画文件传输协议、大小限制、格式以及硬件确认机制：云端列表/上传/删除已接，142/143/144 从后端 URL 到硬件的下发与确认仍待接。
- 恢复出厂（DP 141）：App 已在解绑前下发，固件收到后的具体行为与是否自行解绑待确认。
- 分享渠道码、Universal Link/App Link。
- OTA 固件通道、升级类型和进度回调。
- 微信、支付宝快捷登录参数；国内手机号一键登录服务。
- 自定义头像已接 APP 后端文件上传、头像更新及资料刷新；存储服务、内容审核和真机端到端仍待验证。
- 正式隐私政策、用户协议、公司主体、客服邮箱与官网域名。
- APP 后端 Swagger 契约已完成代码对接；AI_CONTEXT 记录 2026-09-03 HTTPS 已恢复，但当前代码仍保留临时 HTTP 默认回落。发布前需重新核验 HTTPS 并移除回落，使用真实测试账号验证写接口及后台产品 `broadcastId` 与涂鸦 PID 的映射。本轮未重新探测业务服务器。

## 独立工程范围

原始 PRD 同时列出 PC 管理后台、Java 服务端与 PC 官网。这三部分不是 Flutter 技术架构，建议分别建立：

- Java 服务：用户映射、涂鸦 UID、统计归档、动画元数据、FAQ/消息、App 版本。
- 管理后台：用户、分类/PID、设备、FAQ、管理员权限、系统配置。
- 官网：产品展示、隐私政策、账号注销入口和应用商店合规页面。
