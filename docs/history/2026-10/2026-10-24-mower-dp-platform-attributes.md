# 割草机 DP 改以平台「功能点属性」为准

> 文档类型：Historical Change Record
> 日期：2026-10-24；环境：远程 SSH 服务器
> 分支与起始版本：main / cca4893

## 依据与范围

产品更正：`docs/YUSEN Robot Mower(mz7g3yzaufvoh4ls)_10_24.xlsx` 以「功能点属性」列为准，此前按备注改的 DP3 不采用。备注只用于中文显示名称（DP5 / DP18，功能点属性无中文）和 DP3 拒绝条件。

## 核对结果

- DP3：功能点属性为 standby, smart, spot, goto_charge, edge_mowing, secondary, wait_charge, wait_rain（smart = 1），与 89bb9b6 之前一致；备注「1 random 弃用 / 2 smart …」不采用。
- DP5：15 值顺序与 `MowerStatus` 一致。
- DP18：13 位顺序一致；第 10 位平台写 `spot_out_boundaty`。
- DP13 / 105 / 107 / 109 / 117 / 119 / 120 的取值范围与代码一致。
- 差异未改、待确认：DP116 清单为 `alarm_clear` 故障清除（bool rw），APP 按协议 V3.0 当 `ota_status`；清单标识符 DP117 `charging_status`、DP119 `opearting_time` 与代码日志标识符不同（只影响日志）。

## 改动

- `lib`、`test` 中 DP3 相关内容还原到 b4f1d51（`MowerMode` 8 值、DP115 `val` 旧序号、`waitingOnDock` 含 DP3 = 6/7 及对应用例）。
- `MowerFault.identifiers` 第 10 位改回 `spot_out_boundaty`；`MowerMode`、`MowerFault.identifiers` 注释注明以功能点属性为准。
- 改动说明、docs 导航、AI_CONTEXT 同步。

## 验证

本机无 Flutter/Dart，测试、静态分析、格式化均未运行；未真机。`git diff --check` 通过。

## 回滚

还原对应提交即可。
