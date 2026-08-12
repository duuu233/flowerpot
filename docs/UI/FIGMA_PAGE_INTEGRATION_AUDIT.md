# Figma 页面串联与一致性审计

本记录覆盖当前批次根据 Figma 截图新增或重构的账户、协议、关于及设备设置页面。

## 页面链路

### 账户与资料链路

`首页头像 → 我的 → 账号与安全 → 登录密码 / 修改密码 / 忘记密码`

- 首页多个头像入口统一进入 `AppRoutes.mine`。
- “我的”的账号与安全入口进入 `AppRoutes.settings`，对应 `AccountSecurityPage`。
- 登录密码进入 `AppRoutes.loginPassword`；修改密码进入 `AppRoutes.modifyPassword`；忘记密码复用验证码重置流程。
- “我的”的用户协议和关于入口分别进入 `AppRoutes.agreement` 与 `AppRoutes.about`。
- 登录与注册页面同样提供用户协议、隐私政策入口，不依赖登录状态。

### 设备设置链路

`首页“设置” → 设备设置 → 植物 / 显示 / 听觉 / 触觉 / 震动 / 行为 / 其他设置`

- 首页快捷操作中的“设置”进入 `AppRoutes.deviceSettings`；UI 中没有独立“设备详情”页。
- 七个设置项由一个穷尽式 `DeviceSettingsMenuKind → AppRoutes` 映射负责导航。
- 显示、听觉、触觉、震动和行为均为独立全屏页面；植物选择和其他设置进入已有完整页面。
- 所有设备子页都携带当前 `deviceId`，返回按钮统一回到设备设置页。
- 已删除被完整页面替代且不再可达的 `DeviceSettingsControlSheet`，避免两套交互同时维护。

## 共用组件收口

- `DeviceSettingOrbitIllustration`：显示、听觉、触觉和震动页面共用光晕及语义图标绘制。
- `DeviceToggleSettingsCard`：显示与震动页面共用单开关卡片结构。
- `DeviceSensitivitySettingsCard`：听觉与触觉页面共用互动开关、说明和灵敏度结构。
- `BehaviorScheduleCard`：午休与夜间睡眠复用同一日程卡片。
- 所有页面统一使用 `AppPageScaffold`、`AppPageHeader`、`AppBackButton`、`ResponsiveContent`、`AppSurfaceCard` 和 `AppErrorView`。

## 状态与功能点一致性

| 页面 | 状态字段 | DP |
| --- | --- | --- |
| 显示 | `autoBrightness` | 109 |
| 听觉感知 | `soundInteraction` / `soundSensitivity` | 110 / 111 |
| 触觉感知 | `touchInteraction` / `touchSensitivity` | 112 / 113 |
| 震动设置 | `vibration` | 114 |
| 行为-午休 | `napEnabled` / `napPeriod` | 115 / 116 |
| 行为-夜间睡眠 | `nightEnabled` / `nightPeriod` | 117 / 118 |

- 触觉与震动的状态用语统一为“已启用 / 已禁用”。
- 听觉与行为沿用设计稿的“已开启 / 已关闭”。
- 时间段统一以 `HH:mm-HH:mm` 写入设备，跨日只在展示层添加“次日”。

## 回归覆盖

- 每个设备子页均覆盖 375 × 812、320 × 568、缺失设备和入口路由。
- 所有开关和 Slider/时间选择均覆盖对应 DP 写入。
- 账号与安全页面覆盖登录密码、修改密码和忘记密码入口。
- 协议页面同时具备登录/注册公共入口与“我的”入口；关于页面由“我的”入口进入。
- 最终静态分析与全量 Widget 测试结果记录在各页面实施文档中。
