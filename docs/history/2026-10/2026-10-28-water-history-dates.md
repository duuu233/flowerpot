# 需水状态页（水位 / 土壤湿度）周 / 月补日期

> 文档类型：Historical Change Record
> 日期：2026-10-28；环境：远程 SSH 服务器
> 分支与起始版本：main / b9a2b22
> 前序：[2026-10-28 亮度滑条与光照页周 / 月日期](2026-10-28-brightness-throttle-light-dates.md)

## 依据与范围

用户：水位和土壤湿度页的周、月也一起补上日期。两者同在需水状态页（页内切换指标），只改这一页；报表页未改。

## 改动

- `HistoryPeriod.dateTicks(count, ticks)`：折线图等距日期刻度，取点规则与 `relativeTicks` 相同，文字为 `M/d`（最后一点 = 昨天逐天回推）。
- 需水状态页：周 / 月日期条改用 `windowDateLabel`（首尾日期区间），横轴改用 `dateTicks`；日视图不变。
- 测试：`status_history_date_window_test.dart` 新增 `dateTicks` 一条（与相对刻度点数一致、首尾日期、少于 5 点逐点、空数据）。
- 文档：改动说明第四节扩为「光照、需水状态页」；PRODUCT_RULES、光照页 UI 说明、AI_CONTEXT 同步。

## 验证

本机无 Flutter / Dart SDK，测试未运行，未编译、未真机。待本地：`flutter test test/features/devices/status_history_date_window_test.dart`。

## 回滚

撤销本次提交即恢复需水页相对刻度；`dateTicks` 为新增方法，无其他调用方。
