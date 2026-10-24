# 割草机工作时间倒计时：待机、休眠、关机、离线时隐藏

> 文档类型：Historical Change Record
> 日期：2026-10-24；环境：远程 SSH 服务器
> 分支与起始版本：main / 40fd2e8

## 依据与范围

产品口径：机器待机、休眠、关机（离线）三个状态隐藏倒计时。此前定稿为「不隐藏，设置后一直显示」。

## 判定

| 状态 | 依据 |
| --- | --- |
| 待机 | DP5 = 0 standby |
| 休眠 | DP5 = 2 sleep（协议文案「关机」，APP 状态胶囊沿用协议文字） |
| 关机 | DP113 shutdown_report 报 true 且未再开机（`MowerDevice.shutdown`，胶囊显示「已关机」） |
| 离线 | 设备在线状态为 false（`MowerDevice.online`，与下发前「设备已离线」同一判断） |

任一成立即隐藏。DP5=2 与 DP113 两种「关机」都算，避免口径歧义。

## 改动

- `MowerDevice.visibleWorkEndsAt`：上述状态返回 null，否则返回 `workEndsAt`。只影响显示，`workEndsAt` 及本机存储不动，倒计时照常走，离开这些状态后按原终点接着显示（可能已减少或为「0分」）。
- `MowerControlPage` 状态胶囊改传 `visibleWorkEndsAt`；页面已随设备通知刷新（DP5 上报、在线 / 关机变化都会通知）。
- `MowerWorkCountdown`、`MowerStatusCard` 注释口径同步。
- 用例：`mower_work_countdown_test` 新增待机 / 休眠隐藏、其余状态显示、DP113 关机隐藏且复位后恢复、离线隐藏。

## 已知影响

- 设备尚未上报 DP5 时状态默认待机，倒计时也随之隐藏（胶囊本身显示「待机」，两者一致）。
- 只隐藏不清终点：取消任务回待机后，若机器经面板或计划再次进入作业，旧终点会重新显示；APP 新下发 DP119 时照常重计。

## 验证

本机无 Flutter/Dart，测试、静态分析、格式化均未运行；未真机。`git diff --check` 通过。

## 回滚

还原对应提交即可，本机存储格式未变。
