# 割草计划页跟随设备：进页现读 DP101

> 文档类型：Historical Change Record
> 日期：2026-11-03；环境：远程 SSH 服务器
> 分支与起始版本：main / 9b1ef34

## 依据与范围

需求：与同日区域设置类似，设备那边也能设置割草时间段，App 需要监听设备回传的数据并更新 App 内的割草计划。

## 核查结论

- 计划页早已跟随设备上报：`MowerPlanPage` 不存计划副本，`ListenableBuilder(listenable: MowerDevice)` 每次重画都读 `MowerDevice.schedule`（图表、合计、修边勾）。设备上报 DP101 经 `_syncFromDevice` → `_applyReported` 解码更新 `schedule` 并 `notifyListeners`，页面随之刷新。
- DP101 不乐观显示：`setSchedule` 下发后不改本地值，等设备返回有效 DP101 才更新，期间 `schedulePending` 锁住页面。
- 编辑弹层与长按删除已处理「期间设备改了」：保存时 `_apply` / `_mergeSlot` 只覆盖用户改过的字段，其余取设备当前值；删除确认后核对目标时段未变才删，变了提示重新长按。
- 首页计划卡同样监听 `MowerDevice`。
- 与区域设置页修复后的差异只有一处：计划页进页不现读 SDK，依赖绑定时读的快照与之后的实时上报。

## 改动

- `mower_device.dart`：`rereadDps` 支持 DP101——读前取 `_scheduleReadSequence`，读回时序号已被更新的实时上报 / 快照推进就丢掉这次的 DP101；DP101 不按「等待回显」跳过（本来就不乐观显示）；读到后 `_rememberSchedule(…, '进页现读')` 记入联调日志与临时解析窗口。DP103 等其它 DP 规则不变。
- `mower_plan_page.dart`：进页 `rereadDps([DP101])`；注释写明停留期间靠 `ListenableBuilder` 跟随上报。
- 测试 `mower_pages_test.dart` 新增一例：进页现读拿到绑定后才变的计划；停留时上报 DP101，合计由 2 小时变 3 小时 30 分钟，且不下发。

## 未改

- 编辑弹层打开期间设备改了同一天的时段，弹层内容不实时变化；点保存时按上面的合并规则落到设备当前值上。

## 验证

本机无 Flutter / Dart，analyze、format、测试、编译均未运行；未真机。`git diff --check` 通过。需本地执行：

```bash
dart format lib test
flutter analyze
flutter test test/features/mower/mower_pages_test.dart test/features/mower/mower_schedule_source_test.dart
```

真机：停在割草计划页，在机器上改时段，页面应随即刷新，联调日志出现「上报 ← 割草机 DP101」与逐字节解析；若无反应且日志没有 DP101 上报，需固件确认本地修改是否上报 DP101。

## 回滚

还原对应提交即可。
