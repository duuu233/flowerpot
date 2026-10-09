# 割草机首页按钮 loading 对齐与离线 Wi-Fi 置灰

> 文档类型：Historical Change Record
> 日期：2026-10-09
> 环境：办公室（work）
> 分支与起始版本：main / 18dbe2a
> 范围：割草机首页 UI
> 当前权威文档：PRODUCT_RULES.md §4.10

## 背景与目标

用户反馈「继续」按钮点击后的转圈位置或大小与另外三个按钮不一致，并要求核查设备离线时设备图下方的 Wi-Fi 图标是否置灰。

## 变更内容

- `mower_control_page.dart`：四颗按钮继续共用 `_ActionButton`，普通图标和 loading 放在同一个 40×40 槽位；进度条显式固定 24×24、居中、padding=0，线宽 2.6 与原品牌色不变，文字行与按钮尺寸不变。修正旧的「整颗按钮换转圈」注释。
- `widgets/mower_status_card.dart`：原离线图标只降低到 30% 透明度，仍是原青色；Wi-Fi 断开改用 `MowerColors.inkSecondary` + srcIn 着灰，在线恢复原图；蓝牙保持原有压淡方式。
- 更新 PRODUCT_RULES、AI_CONTEXT、文档与历史索引。

## 关键决策

- 不创建独立的「继续」按钮或 loading 组件，统一四颗布局并显式约束进度条，避免尺寸与内边距依赖主题。
- Wi-Fi 图标继续读设备 SDK 分通道状态（MQTT / LAN / Cloud 任一在线），不使用手机 Wi-Fi 开关，也不因蓝牙在线而点亮 Wi-Fi。
- `MowerBleGate.enabled` 默认关闭的现有产品口径不变；本轮只改 loading 的展示，不开启控制前蓝牙预检。未改下发、回显、离线门禁或重连逻辑。

## 外部操作

核对当前环境、Git 身份与干净工作区；main 先 pull --ff-only（已是最新），刷新本机 CodeGraph；未调用外部业务接口、未部署或打包。

## 验证结果

- Flutter 3.44.6 / Dart 3.12.2：本轮两个源码文件 analyze 无问题。
- 现有 mower_pages_test + mower_status_card_test 中的首页按钮、蓝牙预检和充电状态卡回归共 10 条通过。
- 额外运行 mower_live_test 的 3 条设备层用例均失败：离线失败消息集合为空；Wi-Fi 离线降级用例未收到预期下发；DP113 关机日志筛选实际 4 条而预期 1 条。该测试没有使用本轮两个 UI 文件，本轮未修其基线问题，不能宣称设备层离线回归通过。
- 本轮改动区域格式化；去除无关历史代码的格式变化。diff 检查、信息隔离检查及 CodeGraph 同步核对。

## 未完成项与风险

未新增视觉快照用例、未在真机上复核转圈位置与设备离线到恢复在线的颜色切换；真实 SDK 的状态及时性仍需现场确认。未运行全量测试或平台构建。

## 回滚或恢复

可回退本次 UI 提交；不会修改设备 DP 契约、固件或持久化数据。
