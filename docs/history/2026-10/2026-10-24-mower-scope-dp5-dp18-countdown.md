# 割草机改动范围收窄为 DP5、DP18 与倒计时隐藏

> 文档类型：Historical Change Record
> 日期：2026-10-24；环境：远程 SSH 服务器
> 分支与起始版本：main / 592111d

## 依据与范围

产品再次确认：按平台功能点清单，本次只同步首页状态（DP5）、黄色提示框（DP18），以及待机 / 休眠 / 关机 / 离线时隐藏倒计时；工作模式（DP3）不动。

## 核对结果

- `lib`、`test` 中 DP3（`MowerMode` 8 值、编号、显示名、`sendable`、DP115 回执匹配、在桩等待判定）与当天改动前的 13f856a 一致，只差 592111d 在 `MowerMode` 上加的一段注释。
- 保留的改动：DP5 新增 12 / 13 / 14 与平台显示名、DP5=12 黄条脱困提示；DP18 平台显示名与第 10 位标识符 `spot_out_boundaty`；`MowerDevice.visibleWorkEndsAt` 隐藏倒计时。

## 改动

- `MowerMode` 注释还原为 13f856a 原文，`git diff 13f856a -- lib test` 不再含 DP3 内容。
- 改动说明标题改为「状态、告警与倒计时」，删去工作模式一节、DP3 / DP116 相关待确认与 DP3 验收项，注明 DP3 不改。
- docs 导航、AI_CONTEXT 同步（顺带把 DP18 第 10 位标识符的旧说法改为 `spot_out_boundaty`）。

## 验证

本机无 Flutter/Dart，测试、静态分析、格式化均未运行；改动只涉及一处注释，未真机。`git diff --check` 通过。

## 回滚

还原对应提交即可。
