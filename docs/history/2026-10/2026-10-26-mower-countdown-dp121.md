# 割草机工作时间倒计时改以 DP121 当前计划为准

> 文档类型：Historical Change Record
> 日期：2026-10-26；环境：远程 SSH 服务器
> 分支与起始版本：main / f215b84（协议 V3.0 新增 DP121）

## 依据与范围

协议 V3.0 固件基线 2026-10-26 新增 DP121 `schedule_current`（string/ro，JSON `{st,et,now}`，UTC 秒）。用户要求据此完善倒计时整个逻辑。产品报告：`docs/reports/2026-10-26-割草机倒计时改用DP121说明.md`。

## 改动

- `MowerDp.scheduleCurrent = 121`、标识符 `schedule_current`；文件头改为 26 个 DP、基线 2026-10-26。
- 新增 `MowerCurrentPlan`（`lib/src/features/mower/mower_current_plan.dart`）：三字段均为 0~0xffffffff 整数才认（字符串 JSON 或 Map）；`active` = st>0 且 et>st；`remainingSeconds` = max(0, et−now)；`samePlan` 只比 st/et，`sameFrame` 三字段全比。
- `MowerWorkCountdown`：去掉 SharedPreferences 的 `load` / `save`，新增 `endsAt(plan, receivedAt)`；分钟取整、下次刷新、文案不变。
- `MowerDevice`：新增 `currentPlan`；`_applyReported` 处理 DP121——新帧时 `workEndsAt = clock() + remainingSeconds`，同一帧（整包快照反复刷入）不动，无计划为 null，认不出的帧丢弃；计划身份变化时记日志（计划起止、剩余、本机终点 / 无当前计划）。`setOperatingTime` 不再重设倒计时；bind 不再从本机存储读终点；`visibleWorkEndsAt` 隐藏规则不变。
- 注释：控制页、状态卡说明改为 DP121 来源。
- 测试 `mower_work_countdown_test.dart`：删除 DP119 计时、本机读回、其它设备存储三条；新增 DP121 解析边界、快照起算 / 同帧快照不动 / 兜底新帧按机器差值重设 / 换计划 / 坏帧保留 / 无计划收起、DP119 不再计时三条；隐藏规则用例保留。

## 决策

- 基准用「收到时本机时刻 + et−now」（协议 App 侧处理口径），不拿 et 直接和手机时钟比，避免手机与机器时钟差。
- 只在新帧时重设：DP121 每次兜底 now 都变，快照路径会把同一旧值反复刷入，若每次都重设会把终点往后推。
- 待机 / 休眠 / 关机 / 离线隐藏按 2026-10-24 产品口径保留。

## 验证

本机无 Flutter/Dart，单元 / 组件测试、静态分析、格式化均未运行；未真机。`git diff --check` 通过。

## 剩余

- 有 Flutter 的环境跑 `flutter test test/features/mower/mower_work_countdown_test.dart` 及 mower 目录全量。
- 真机按报告第五节验收；旧固件无 DP121 时不再显示倒计时，需确认设备均已升级。
- 首次进入页面使用云端缓存帧，最多偏差一个兜底周期（60s）。

## 回滚

还原对应提交即可；本机残留的旧倒计时存储键不影响功能。
