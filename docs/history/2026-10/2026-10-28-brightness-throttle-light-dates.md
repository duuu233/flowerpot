# 显示页亮度滑条快速操作不再来回晃；光照状态页周 / 月补日期

> 文档类型：Historical Change Record
> 日期：2026-10-28；环境：远程 SSH 服务器
> 分支与起始版本：main / 506e876
> 当前权威文档：`history/other/PRODUCT_RULES.md`（§4.16 显示页条目、光照历史条目，均标 2026-10-28）

## 一、显示页亮度滑条

### 依据

用户：「屏幕亮度」滑条加节流防抖；操作过快时操作的数据和回显的数据冲突，滑条来回晃动。

### 原因

- `FlowerpotState.updateSetting` 下发成功、期间没收到该 DP 上报时，会把下发值直接写进设备快照（乐观值）。
- 页面松手后的回显保护（2026-10-21）只看「快照 == 最终值」持续 500ms：最终值刚下发完，快照就已经是最终值（乐观值），
  500ms 后交还设备状态；此时拖动中发出的中间值，设备的真实上报还在路上，随后到达把滑块拉回中间值，再到最终值上报又拉回来——即用户看到的来回晃。
- 原 120ms 限频下中间值较多，迟到的上报也多。

### 改动

- `FlowerpotState.dpReportRevision(id, dp)`：公开某 DP 的累计上报次数（设备报了就算，值不变也算），只读。
- `display_settings_page.dart`：
  - 拖动限频 120ms → 300ms，仍串行、只发最近值，松手立即补发最终值；
  - 本次调节（滑块离开设备状态起到交还为止）记成功下发次数与 DP168 上报基线；和上一次已下发值相同不重发；
  - 回显确认改为：上报次数 − 基线 ≥ 成功下发次数，且快照最新值等于最终值，再稳定 500ms 才交还；最长 5 秒、失败立即恢复、新手势 / 切自动 / 离线 / 退出取消，均保持原规则。
- 测试：原有用例中依赖 120ms 的 7 处时点改为 300ms（119ms → 299ms），判据不变；新增「乐观值不提前交还，迟到的中间值上报不拉回滑块」「拖回上次已发值不重发」两条。

## 二、光照状态页周 / 月日期

### 依据

用户：光照状态页历史记录周与月没有日期显示，需要补充。原做法依据设备文档 §4.5 第 3 条（周 / 月只标相对刻度，不标具体日期），本次按用户要求改，已在 PRODUCT_RULES 记录。

### 改动

- `HistoryPeriod` 新增 `barDate` / `shortDate` / `dateBarLabels` / `windowDateLabel`：最后一点 = 昨天，第 i 点 = 今天 − (点数 − i) 天，与原 `relativeDayLabel` 同一算法。
- 光照状态页：周 / 月日期条由「近 N 天日均」改为首尾日期区间；柱状图标签由「N天前」改为 `M/d`，标注位置不变（周每 7 根、月每 30 根、最后一根）。无数据时日期条仍回退原窗口文案。
- 水位 / 土壤湿度页、报表页未改（仍用相对刻度）。
- 测试：`status_history_date_window_test.dart` 新增 3 条（日期回推、标签位置与原相对标签一致、日期区间与空数据回退）。

### 已知限制

周帧帧头带有日期，但设备文档未说明其含义（报帧日 / 最近聚合日），本次未据此对齐，沿用「最后一点 = 昨天」；设备断电缺天时日期只是按点数回推。

## 文档

- 报告 `docs/reports/2026-10-27-花盆APP今日改动说明.md` 改名为 `docs/reports/2026-10-27至10-28-花盆APP改动说明.md`，追加第三、四节；`docs/README.md` 索引同步。
- `PRODUCT_RULES.md`、`UI/DISPLAY_SETTINGS_IMPLEMENTATION.md`、`UI/LIGHT_STATUS_PAGE_IMPLEMENTATION.md` 补 2026-10-28 口径。

## 验证

- 本机无 Flutter / Dart SDK，`flutter analyze` / `flutter test` 未运行，未编译、未真机。人工核对了原有显示页用例在新逻辑下的时序与判据。
- 待本地运行：`flutter analyze`、`flutter test test/features/devices/display_settings_page_test.dart test/features/devices/status_history_date_window_test.dart test/features/devices/light_status_page_test.dart`。

## 回滚

撤销本次提交即恢复 120ms 限频与原回显保护、光照页相对刻度；`dpReportRevision` 为新增只读方法，回滚无副作用。
