# toast 去掉来源前缀，直接给内容

> 文档类型：Historical Change Record
> 日期：2026-09-10
> 环境：SSH（无 Flutter/Dart 工具链）
> 分支与起始版本：main / 863b02b
> 范围：`lib/src/state.dart`、失败页与登录页注释、对应用例
> 当前权威文档：`AI_CONTEXT.md`

## 背景

产品要求：toast 里去掉 `接口-` / `APP-`（以及同源的 `涂鸦-`）前缀，直接输出内容。

这些前缀由 `FlowerpotState._tagged` 统一拼在失败文案前面，本意是「一眼看出是谁拒绝了这次
请求」。对排查有用，对用户没用——「接口-406 请重新登录！」里真正有信息量的只有后半句。

## 变更内容

- `_tagged` 改名 `_diagnostic`，**只服务诊断行**，不再进用户可见文案。
- `_run` 里四条出口全部改为直接给原文：`AuthValidationException` / `TuyaException` /
  `ApiException` / 兜底的未预期异常。
- 两处写死的前缀一并去掉：`APP-wifi_scanning 正在扫描附近网络，请稍候` →
  `正在扫描附近网络，请稍候`；`APP-busy 请等待当前操作完成` → `请等待当前操作完成`。
- **诊断行保留标签**：`sessionDiagnostics`（设备列表页底部那行可长按复制的
  `uid · 家庭 · 设备 N 台 · 失败原因`）与 `_backendSessionError` 仍走 `_diagnostic`。
  那两处本来就是给排查看的，去掉来源反而查不动。

## 关键决策

- **来源信息没有丢**：`ActionResult.code` 一直带着原始错误码（`1006`、`406`、`invalid_input`
  …），页面需要时可以自己展示——配网失败页就是这么做的，认得的码补在括号里
  （`手机没有连上设备热点（hotspot_join_cancelled）`）。
- **只去前缀，不动其余**：`pairViaHotspot` 往文案尾部拼的分步耗时（`｜令牌 812ms · 连热点…`）
  没有动，产品这次要求的是前缀。

## 验证结果

- 本机**没有 Flutter/Dart SDK**，`dart format` / `flutter analyze` / `flutter test` 均未执行。
  改动过的文件过了自写的括号配平检查，并逐行通读。
- 用例改动（**未运行**）：`pairing_page_test.dart` 的 `'涂鸦-pair_failed 配网失败'` →
  `'配网失败'`；`pairing_failure_page_test.dart` 的样例文案去掉 `涂鸦-` 前缀。
- 全仓检索确认：`lib/` 与 `test/` 里已无用户可见的 `接口-` / `涂鸦-` / `APP-` 前缀，
  只剩 `_diagnostic` 自身与说明性注释。
- **真机未验。**

## 未完成项与风险

- 诊断行的格式没变，排查文档（若有引用示例）仍然成立。
- 若之后有人想在 toast 里看错误码，正确做法是**页面按 `code` 自己拼**，不要把前缀加回
  `_run`——那会把所有 toast 一起污染。
