# 割草机 DP5 状态名称与 DP18 黄条文案改为平台名称

> 文档类型：Historical Change Record
> 日期：2026-10-24；环境：远程 SSH 服务器
> 分支与起始版本：main / f626e65

## 依据与范围

产品 2026-10-24 给出 DP5 工作状态 15 个值、DP18 故障告警 13 位的平台名称，要求首页状态胶囊与 DP18 黄条按此显示。标识符、序号、位定义均与协议 V3.0 一致，只改显示文字。

## 改动

- `MowerStatus` 显示名：mowing 随机割草、sleep 休眠、goto_charge 回桩、paused 暂停、edge_mowing 绕边割草、wait_charge 等待充电、wait_rain 等待雨停、secondary 去第二区域、escaping 脱困中、goto_charge_low_pwr 低电回充、goto_charge_rain 雨滴回充；standby / spot_mowing / fault / stop 不变。注释去掉「2 是关机不是休眠」的旧口径。
- `MowerFault.messages`（首页黄条与「设备告警」弹窗共用）：13 位由「现象 + 处理建议」整句改为平台名称（左电机故障 … 刀盘电机故障）。
- `MowerFault.identifiers` 第 10 位 `spot_out_boundaty` 改为平台写法 `spot_out_boundary`，只用于日志。
- `MowerStatusCard` 注释示例同步。
- 用例：codec / pages / live_notice / work_countdown 中的状态名与故障文案断言同步。
- 文档：DP5 改动说明新增第 4 节对照表并全文换用新名称；AI_CONTEXT 同步。

## 未改

- DP3 工作模式名称、本机机器日志文字（`MowerMachineLog`）、DP113「已关机」、DP5=12 黄条「机器陷入坑洼，正在脱困」。

## 验证

本机无 Flutter/Dart，测试、静态分析、格式化均未运行；未真机。`git diff --check` 通过。

## 回滚

还原对应提交即可，无存储或协议变更。
