# 设备在线状态

> 文档类型：Product / Integration Contract
> 状态：Active
> 最后核验：2026-10-21（在线轮询3秒、清单刷新逐项合并；未真机、未运行测试）
> 适用范围：花盆与割草机设备列表及共享在线字段

## 唯一来源

设备列表的在线/离线胶囊直接使用涂鸦 SDK 设备模型的 `online/isOnline`。花盆和割草机使用同一份规则。状态由设备清单、SDK 设备状态推送、前台 SDK 状态读取同步；不使用 APP 后端、手机网络是否可用、蓝牙连接成功、DP 收到与否、信号探测超时、计时或命令成败自行判在线/离线。

- `FlowerpotState.devices` / `deviceById` 原样返回设备在线字段；不再套本地不可达集合。
- 前台每 3 秒读涂鸦 SDK 缓存（2026-10-21 由 8 秒缩短），回前台同步缓存及清单。读失败、无记录保留最后收到的 SDK 状态，不把未知改成离线。
- 已移除 20 秒 `requestWifiSignal` 探测调度及连续两次超时判离线逻辑；该原生能力仍可用，但不参与在线状态维护。
- SDK 查询不能覆盖查询发起后收到的新 SDK 快照/推送，旧登录会话的迟到查询丢弃。设备清单查询期间来过推送时，只把那几个DP/在线值叠到新清单上，其余字段仍用这次 SDK 新值（2026-10-21，此前整台退回旧快照）；状态层只保护清单返回之后才到的推送。Repository 同步 SDK 在线查询结果到 DP 合并快照，DP-only 报文不恢复旧在线值。
- `online` 可代表 SDK 认可的可通信状态，包括支持的 Wi-Fi/LAN/BLE 通道；不自行改成只看云端或只看 Wi-Fi。

## 双端桥接

| 平台 | 设备清单与状态 | 限制 |
| --- | --- | --- |
| Android | `DeviceBean.getIsOnline/isOnline`、`IDevListener.onStatusChanged`、`deviceOnlineStates` | `onNetworkStatusChanged` 的网络可用值不写入设备 `online`；DP 更新不合成在线值 |
| iOS | `ThingSmartDeviceModel.isOnline`、`deviceInfoUpdate`、`deviceOnlineUpdate`、`deviceOnlineStates` | 仅转发 SDK 模型字段，不根据本地网络或 DP 推断；Windows 未能 Xcode 编译 |

官方契约参考：[Android 设备回调](https://developer.tuya.com/en/docs/app-development/devicemanage?id=Ka6ki8r2rfiuu)、[iOS 设备模型](https://developer.tuya.com/en/docs/app-development/ios-saas-commercial-lighting-device-manager?id=Kampuheit31oz)、[iOS Delegate 接口](https://tuya.github.io/tuyasmart_home_ios_sdk_api_reference/ios-arm64_2_thing_smart_device_core_kit_8framework_2_headers_2_thing_smart_device_8h_source.html)。

## 列表与控制

列表状态胶囊只显示 SDK 的“在线/离线”。割草机 DP113 的“已关机”不覆盖这个胶囊；控制页仍按设备上报保留已关机提示和命令安全门禁。花盆离线不可进控制页；割草机离线仍允许进入、导航与编辑，控制和保存按钮不按online禁用；点击提交弹「设备已离线」，留在当前页面，不发DP、不清参数表单草稿。真实命令和SDK通道结果不作成功伪装。

割草机发命令时通道选择依据 `deviceLinkState` 返回的 SDK Wi-Fi/LAN/MQTT/Cloud/BLE 值，不再受本地探测不可达集合影响。列表总在线值和控制页的独立 Wi-Fi/BLE 图标职责不同；本轮没有补齐 iOS `deviceLinkState`，原有能力缺口仍由 `MOWER_DP_GAP_REPORT.md` 维护。

## DP实时更新（2026-10-20）

花盆与割草机均通过SDK的设备DP监听→EventChannel→Repository→FlowerpotState更新，割草机继续分发mowerReports；不通过自建网络心跳伪造DP。Android/iOS设备监听对所有上报DP生效，不需要逐项订阅。前台3秒在线缓存查询仅补在线状态并重试尚未注册的设备监听，不是每3秒向设备查询所有DP；后台暂停，返回前台刷新清单。设备未上报、固件不上报及SDK链路断开不能由App生成数值。

同一DP的数字键/字符串键统一合并，避免旧字符串键掩盖新值。晚到设置成功答复不能覆盖期间收到的同DP上报；设备清单刷新和家庭查询期间到达的较新状态优先，最新SDK设置快照替换旧乐观缓存。下发中的本地拖动值仅作草稿展示，松手收敛后回到共享设备状态。

## 验证与真机验收

回归文件：`test/state_reachability_test.dart`（已改为 SDK 唯一来源规则）、`test/tuya/device_updates_test.dart`、`test/features/devices/device_list_page_test.dart`，控制与固件流程由 mower_pages / firmware_reminder 回归。

真机需检查：SDK 在线但手机断网或信号查询不回应时列表不自行变离线；收到 SDK 离线/上线回调后刷新；DP-only 报文不改 online；后台回来从 SDK 补读；DP113 真值仍能限制控制操作，而列表只随 SDK online；蓝牙连接不由 APP 手动推定列表在线。等待云端判定离线的延迟由涂鸦决定。

## 离线操作门禁

`DeviceOnlineBody` 仅对花盆离线显示只读提示并淡化/禁止正文。识别为割草机时原样显示child，不遮挡、淡显或屏蔽焦点；控制/计划/设置和区域、雨淋、时间、语言、设备信息均恢复交互。在线布局不变。

割草机页面提交前先用公共提示框反馈离线，不返回设备列表；表单本地编辑可继续，按钮仍保留独立工作状态/关机限制。割草机参数setter在改设备显示前仍检查online与关机；排队发送时仍检查最新状态。`publishMowerDps` 在查询通道前和真正下发前检查共享online，Wi-Fi/BLE通道缓存不能绕过。花盆DP仍走统一离线门禁。改名、查询固件和OTA启动也先检查；查询返回时离线丢弃新结论，缓存版本不在离线时亮红点。

普通/强制升级提醒仅在线允许弹出，弹出后离线即关闭；手动新升级在版本查询及用户确认后重验在线。设备已进入OTA的回调仍正常维护，离线可重新查看已有进度，安装待核验不清目标、不伪造终态；离线时不清本次状态发起重查。
