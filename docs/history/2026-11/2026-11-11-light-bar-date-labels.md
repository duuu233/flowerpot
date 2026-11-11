# 光照状态页周 / 月柱状图只有最后一天有日期

> 文档类型：Historical Change Record
> 日期：2026-11-11；环境：远程 SSH 服务器
> 分支与起始版本：main / 4c76d04
> 前序：[2026-10-28 亮度滑条与光照页周 / 月日期](../2026-10/2026-10-28-brightness-throttle-light-dates.md)

## 依据与范围

用户：光照状态页光照度的周、月历史只有最后一天显示日期，前面都没有；其它页面一并检查。

## 原因

`HistoryPeriod.dateBarLabels` 按固定间隔标字：周每 7 根、月每 30 根（光照页传 `every: 30`），从最后一根往左数。周包常见 7 个点、月包常见 31 个以内的点，固定间隔下只有最后一根（月 31 根时再加第一根）落在标字位置上。

## 改动

- `HistoryPeriod.barLabelled(index, count, maxLabels: 7)`：间隔 = ⌈(count − 1) ÷ (maxLabels − 1)⌉，点数 ≤ 7 时每根都标；从最后一根往左每隔一个间隔标一根，整轴最多 7 个。例：7 根全标，28 根标 2/7/12/17/22/27，31 根标 0/5/…/30，180 根每 30 根一个。
- `dateBarLabels`、`relativeBarLabels` 改用它，参数 `every` 换成 `maxLabels`；光照页周 / 月统一调 `dateBarLabels(count)`。
- 测试：`status_history_date_window_test.dart` 原 28 根用例的取样位置按新间隔更新；新增间隔用例（1 / 7 / 28 / 30 / 180 根的标字位置，1~180 根最后一根必标、不超过 7 个、2 根以上至少 2 个，7 根周包每根都有日期）。

## 其它页面检查

- 需水状态页（水位 / 土壤湿度）周 / 月：折线横轴用 `dateTicks` 等距取 5 个刻度（点数不足 5 逐点），每个刻度都有日期，无此问题，未改。
- 空气温度、相对湿度：只有日视图，按时刻标整点，无此问题。
- 报表页：路由仍在但 App 内无入口，只标首尾相对刻度，未改。

## 验证

本机无 Flutter / Dart SDK，测试未运行，未编译、未真机。待本地：`flutter test test/features/devices/status_history_date_window_test.dart`。7 根时每根约 37px 宽、`M/d` 约 30px，375 宽屏预计不重叠，需真机确认。

## 回滚

撤销本次提交即恢复固定间隔。
