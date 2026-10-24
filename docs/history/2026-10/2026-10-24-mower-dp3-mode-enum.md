# 割草机 DP3 工作模式改为 5 值枚举

> 文档类型：Historical Change Record
> 日期：2026-10-24；环境：远程 SSH 服务器
> 分支与起始版本：main / b4f1d51

## 依据与范围

产品 2026-10-24 给出 DP3（枚举序 = 传输值）：0 standby 待机（取消任务回主页）/ 1 random 弃用 / 2 smart 随机割草 / 3 spot 定点 / 4 goto_charge 回充；smart 被拒条件为休眠、急停、报警、OTA 中、开盖，spot 另加在充电、在边界线外，goto_charge 同 smart。协议 V3.0 原为 0 standby / 1 smart / 2 spot / 3 goto_charge / 4~7 占位与在桩等待。

## 改动

- `MowerMode`：改为 standby / random / smart / spot / gotoCharge 五值，gotoCharge 显示名「回充」；`sendable` 排除 random。
- 下发仍按标识符；DP115 回执 `val` 与序号型上报按新序号匹配（smart = 2、spot = 3、goto_charge = 4）。
- `MowerDevice.waitingOnDock` 去掉 DP3 = 6/7 分支，只看 DP5 = 9/10；`setMode` 拦截日志与控制页注释同步。
- 用例：codec（序号、可下发、序号解析）、lifecycle 与 pages 的 DP115 `val`、machine_log 的 `val` 同步；删去 DP3 = wait_charge / 7 的置灰用例。
- 拒绝条件逐条对照拒绝理由 V1.0（16/18/19/21/23/26/32/33/54），APP 均已有文案，未改。
- 文档：DP5 改动说明新增第 5 节；AI_CONTEXT 同步。

## 风险

设备若仍按 V3.0 旧序号回执，DP3 拒绝原因将匹配不上而不弹；仓库内协议 V3.0 文档的 DP3 表仍是旧序号，需设备侧更新。

## 验证

本机无 Flutter/Dart，测试、静态分析、格式化均未运行；未真机。`git diff --check` 通过。

## 回滚

还原对应提交即可，无存储变更。
