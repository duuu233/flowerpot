# 智能花盆 1.0 PRD 落地清单

来源：`智能花盆1.0开发方案.docx`。

## App 已实现

| 一级模块 | PRD 内容 | 实现位置 |
| --- | --- | --- |
| 账号 | 国内手机号、海外邮箱、验证码/密码、注册、找回/修改密码、退出、注销、头像和用户名 | `features/auth`、`features/profile` |
| 首页 | 已配网设备列表、在线/信号/电量/充电、添加和删除设备 | `features/home`、`features/devices` |
| 配网 | 2.4 GHz Wi-Fi、Token、创建默认家庭（当前固定 AP 模式；搜索与选择设备两页仍是模拟，未接入设备发现） | `pairing_page.dart`、原生 Tuya bridge |
| 首页与状态详情 | 植物、陪伴天数、天气、水位、土壤、光照/PPFD/DLI、温度、湿度、电池 | `features/home`、`features/devices/presentation/*_status_page.dart`、`reports_page.dart` |
| 报表 | 水位/湿度日周月、PPFD 日、DLI 周月、温湿度/电池趋势 | `reports_page.dart` |
| 定制动画 | 图片列表、上传、同步、置顶、删除 | `animations_page.dart` |
| 设备设置 | 名称、植物、硬件信息、OTA、分享/解绑/恢复出厂 | `device_settings_page.dart` |
| 感知设置 | 自动亮度、声音/触摸开关与灵敏度、振动 | `device_settings_page.dart` |
| 行为 | 中午小憩、夜间睡眠时间段和开关 | `device_settings_page.dart` |
| 本地化 | 位置天气、重置位置、温标、12/24 小时 | `device_settings_page.dart` |
| 维护 | 水位校准、修复系统文件、重新配网 | `device_settings_page.dart` |
| 我的 | 中英文、消息开关、App 升级、帮助、隐私、协议、关于 | `features/profile` |

## 需要平台参数后联调

- Android 本机已完成 AppKey、AppSecret、包名、证书 SHA-256、安全 AAR 与 Home/Expansion SDK 初始化验证；账号、家庭、配网和设备链仍需真机与真实账号联调。秘密与安全组件不入库，其他开发环境必须独立配置。联调起点是登录页的「涂鸦 SDK 联调」入口（见 `TUYA_SDK_SETUP.md` 5.3），它直接调用注册、登录、会话与设备列表并显示原始失败码。
- 设备发现（蓝牙或 Wi-Fi 扫描）尚未接入：桥接与 `TuyaRepository` 都没有扫描契约，搜索页和选择页是模拟实现，需要确认产品要用的发现方式后再落地。配网模式当前固定 AP，EZ 快连需要产品确认。
- iOS AppKey、AppSecret、Bundle ID、签名与安全组件仍需配置和验证。
- 产品 PID 与 101–123 DP 的最终对应关系、数据缩放倍率和枚举定义。
- 涂鸦设备数据统计服务的开通范围与统计 API。
- 设备图片/动画文件传输协议、大小限制、格式以及硬件确认机制。
- 分享渠道码、Universal Link/App Link。
- OTA 固件通道、升级类型和进度回调。
- 微信、支付宝快捷登录参数；国内手机号一键登录服务。
- 自定义头像的自有存储、内容审核与合规方案（涂鸦已停止维护其头像上传接口，当前仅保留本地选择预览）。
- 正式隐私政策、用户协议、公司主体、客服邮箱与官网域名。

## 独立工程范围

原始 PRD 同时列出 PC 管理后台、Java 服务端与 PC 官网。这三部分不是 Flutter 技术架构，建议分别建立：

- Java 服务：用户映射、涂鸦 UID、统计归档、动画元数据、FAQ/消息、App 版本。
- 管理后台：用户、分类/PID、设备、FAQ、管理员权限、系统配置。
- 官网：产品展示、隐私政策、账号注销入口和应用商店合规页面。
