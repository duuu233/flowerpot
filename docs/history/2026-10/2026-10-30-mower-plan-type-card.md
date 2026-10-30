# 割草机首页计划卡：DP121 计划类型、手动计划与今日计划

> 文档类型：Historical Change Record
> 日期：2026-10-30；环境：远程 SSH 服务器
> 分支与起始版本：main / 7340950

## 依据与范围

协议 `Grass_Master_Automower_DP协议对接_V3.0.md`（V3.1 增量）与 `Grass_Master_Automower_DP121计划类型_App对接说明_V1.0.md`：DP121 新增计划类型 `t`（0 无计划 / 1 定时计划 / 2 手动计划，MCU_VER ≥ 1.3.5 才带），计划身份改为 `(st, et, t)`。产品同日要求：

1. 去掉首页状态胶囊后面的倒计时；
2. 倒计时为 0 直接显示今日计划，不再看 DP121 类型；大于 0 时 `t=2` 显示手动计划（日期星期读手机，起止取 DP121 st / et），其余显示今日计划；两种都在原「修边」位置显示倒计时，隐藏规则不变（只看 DP121 剩余为 0）；
3. 今日计划：两个时段统一为原「下一任务」字号颜色、去掉「下一任务」文字、每个时段按手机时间显示未开始 / 进行中 / 已结束；修边移到「今日计划」文字后，手动计划不显示修边。

## 改动

- `mower_current_plan.dart`：新增 `MowerPlanType`；`parse` 读 `t`，缺字段或不是 1 / 2 一律按 0，不再因此整帧作废（st / et / now 规则不变）；`samePlan` 改比较 `(st, et, t)`，`sameFrame` 随之含 `t`。
- `mower_work_countdown.dart`：新增 `showsManualPlan`——终点为空或剩余分钟为 0 返回 false，否则只有 `t=2` 返回 true。
- `mower_device.dart`：DP121 日志写出计划类型；计划变化判定随 `samePlan` 带上 `t`（DP119 等待转圈遇到只换类型的新帧也会结束等待）。
- `widgets/mower_work_countdown_view.dart`：原状态卡私有的倒计时组件搬出为 `MowerWorkCountdownView`，行为与 Key 不变（去掉了紧贴状态文字的左间距）。
- `widgets/mower_status_card.dart`：去掉 `workEndsAt` / `workLoading` / `now` 参数与胶囊内倒计时。
- `mower_control_page.dart`：`_TodayPlanCard` 改为 `_PlanCard`（StatefulWidget），接收 DP101 计划、DP121 当前计划、可见终点、DP119 等待与时钟；标题按 `showsManualPlan` 切换；今日计划时段行样式 `brand / 12 / 1.5`，进度色：进行中品牌色、未开始次要灰、已结束浅灰；修边小标签（高 20）跟在标题后；手动计划显示 DP121 起止（本地时间，结束落在次日零点写 24:00）；倒计时放在第一行右侧（无时段时在「暂无割草计划」那行右侧）。卡片在倒计时到点、今日时段开始 / 结束、零点时自行重画。
- 测试：`mower_work_countdown_test.dart` 状态胶囊用例改为倒计时组件与「胶囊不显示倒计时」，补 `t` 解析、三元组身份、`showsManualPlan`、设备只换类型的新帧；`mower_pages_test.dart` 新增计划卡五个用例（定时、手动、倒计时为 0 时 t=2 仍今日计划、旧固件无 t、手动倒计时到点切回今日计划）。

## 决定

- `t` 非法值（字符串、超出 0~2）按 0 处理而不是丢帧：协议只要求缺字段当 0，非法值同样走「今日计划」兜底，避免一个字段坏掉连倒计时都丢。
- DP119 下发后的转圈仍保留，随倒计时一起移到计划卡。
- 手动计划只显示 DP121 这一段，不再列 DP101 的两个时段，也不显示进度。

## 验证

本机无 Flutter / Dart，analyze、format、测试、编译均未运行；未真机，未用带 `t` 的固件联调（固件 1.3.5 尚未落地）。`git diff --check` 通过。需本地执行 `flutter analyze` 与 `flutter test test/features/mower/`。

## 未决

- 平台 DP121 数据长度上限需 ≥ 64 字节（协议 §2），否则新载荷被截断成非法 JSON、整帧丢弃；需平台侧确认。

## 回滚

还原对应提交即可。
