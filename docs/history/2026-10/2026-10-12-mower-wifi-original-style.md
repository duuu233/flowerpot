# 割草机 Wi-Fi 图标恢复原样与状态核查

> 文档类型：Historical Change Record
> 日期：2026-10-12
> 环境：办公室（work）
> 分支与起始版本：main / 61a71b7
> 范围：割草机首页连接图标
> 当前权威文档：PRODUCT_RULES.md §4.10、MOWER_DP_GAP_REPORT.md §1.5 / M01

## 背景与目标

产品要求撤销此前 Wi-Fi 离线着灰的样式，保留原图，并检查在线、断开时能否显示相应状态。

## 变更内容

- `mower_status_card.dart` 去掉 Wi-Fi 专用灰色滤镜和分支；Wi-Fi 与蓝牙均使用原图，在线透明度 1、未连接透明度 0.3，26×26 尺寸不变。
- 增加两组组件回归：分别在蓝牙断开、连接时切换 Wi-Fi 离线→在线→离线，核对透明度、原图无着色和独立显示。
- 更新当前产品口径、上下文、连接能力说明与索引。2026-10-09 的历史记录保持冻结；当时一起修改的按钮 loading 继续保留。

## 关键决策

Android `deviceLinkState` 返回 MQTT、LAN、Cloud 任一在线作为 Wi-Fi 状态；BLE 管理器或 BLE 通道状态另行判断。页面接收设备层的两个独立布尔值，设备层的异步查询保留会话代次保护。不使用手机 Wi-Fi 开关，也不因设备仅通过蓝牙在线而点亮 Wi-Fi。

本轮不改连接、重连或下发规则。iOS `AppDelegate.swift` 仍缺 `deviceLinkState`、`connectDeviceBle` 和 `requestWifiSignal`，这是已有 M01 缺口，不能宣称 iOS 的实时图标判断已验证正常。

## 外部操作

先显式 pull 当前 main，刷新 CodeGraph 后核对 Android 与 iOS 桥接。未请求外部业务接口，未生成 APK、未部署。交付按 main 提交，push 前再次 pull 同名分支。

## 验证结果

- `flutter test --no-pub`：mower_status_card_test、mower_lifecycle_test、mower_pages_test、mower_live_test 共 88 项通过。
- 状态卡与对应测试文件 Dart analyze 无问题；差异检查通过。
- CodeGraph 随交付同步并检查。未运行全量测试、平台构建或真机验证。

## 未完成项与风险

真实设备掉线通知及时性需要现场复核；iOS 分通道查询仍按 M01 跟进。本轮只恢复既有图标表现和核对现有 Android 逻辑。

## 回滚或恢复

回退本次组件与测试改动即可恢复此前着灰样式，不涉及 DP、固件或持久化数据。
