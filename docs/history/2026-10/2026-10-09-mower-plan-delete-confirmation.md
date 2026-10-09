# 割草计划长按删除增加确认

> 文档类型：Historical Change Record
> 日期：2026-10-09
> 环境：办公室（work）
> 分支与起始版本：main / e099ba8
> 范围：割草计划页面与回归测试夹具
> 当前权威文档：PRODUCT_RULES.md §4.19、MOWER_DP_GAP_REPORT.md 附录 A 的 DP101 项

## 背景与目标

产品要求长按计划时间后先提示「计划时间是否要删除？」，确认才删除。同步最新代码后核对发现，图表长按直接调用 `_deleteSlot`，该函数立即清空时段并整周下发；旧用例也断言长按直接删除。此前默认时间、修边与停用时段的修改未覆盖确认流程。

## 变更内容

- `_deleteSlot` 复用 `showAppConfirmDialog`，标题「删除计划时间」、正文「计划时间是否要删除？」、按钮「取消 / 确认」；确认且页面仍挂载后才读取当前周计划并删除目标时段。
- 取消、返回、遮罩关闭均不改变计划、不下发。确认只清空目标天的目标时段，另一时段、修边及其他天保留，继续下发整周 DP101。
- 图表操作说明改为「长按时段确认删除」。空时段默认时间沿用 §4.18。
- 新增两种时段各三条退出用例及一条确认用例（共 8 条）；旧删除后再新建用例增加确认动作。
- 修复阻塞测试编译的 Mock 同名成员：保留接口 `bleScanStops` 事件流，计数器改名 `bleScanStopCalls` 并同步三个断言。
- 割草机页面夹具在 `testWidgets` 内重建单例发送队列，并在刷新后暂停在线轮询；避免队列创建于外层区域而不随假时钟推进、遗留 20 秒 Timer。未修改生产发送与轮询逻辑。

## 关键决策

使用已有公共确认组件，不新增弹框组件；先等待确认，再读取最新周计划，以保留确认期间其他天的更新。设备协议、编码和固件契约不变。

## 外部操作

当前 main 工作区干净后执行 `git pull --ff-only`，从 4a784f6 快进到 e099ba8；保留当前分支。修改前后同步本机 CodeGraph，最终 status 为 up to date。完成后按约定提交，push 前再次执行快进 pull。

## 验证结果

- Flutter 3.44.6 / Dart 3.12.2。
- `flutter test test/features/mower/mower_pages_test.dart --plain-name 长按`：9 条全部通过。
- `flutter test test/features/mower/mower_pages_test.dart test/features/mower/mower_dp_codec_test.dart`：46 条通过、2 条失败。失败均为 DP18 / DP113 告警用例找不到「设备告警」弹框；未涉及本次长按删除路径，不宣称整份回归通过。
- `flutter analyze` 本次生产文件、计划页测试、Mock 与 state_pairing_test 共 5 个文件：无问题。
- 包含 device_search_page_test 的 6 文件分析失败：该旧用例第 308 行构造 WifiScan 缺少必填 networks；本次该文件只改停扫计数器断言，未扩大修复。
- 两条 BLE 发现计数器回归在第一条运行阶段停滞，人工中止；未得到通过结论。
- Dart formatter 已执行；剔除了旧代码无关格式差异。`git diff --check` 通过。

## 未完成项与风险

未运行全量测试、未打包、未真机验证。告警弹框失败、搜索旧用例缺 networks 及配网用例停滞需要另行排查；不把本次局部通过当作全项目通过。真机验收长按 → 取消仍保留、长按 → 确认仅删目标，并核对 DP101 回显。

## 回滚或恢复

如需回滚，撤销本次提交；该变更无存储迁移。回滚会恢复长按直接删除的旧行为。
