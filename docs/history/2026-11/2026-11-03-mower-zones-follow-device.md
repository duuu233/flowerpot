# 割草机区域设置页跟随设备上报刷新

> 文档类型：Historical Change Record
> 日期：2026-11-03；环境：远程 SSH 服务器
> 分支与起始版本：main / 5f56e83

## 依据与范围

反馈：区域设置里区域 2 的配置没生效——在机器上设置了第二区域，App 没反应；最新 App 有问题，旧 App 正常，固件相同。问题：最新版有没有按涂鸦 SDK 上报动态改值。

## 核查结论

- `MowerDevice` 层正常：绑定时读 SDK 设备快照，实时上报 DP103 经 `_applyReported` 用 `MowerZoneCodec.decode` 更新 `zones` 并 `notifyListeners`。DP103 编解码自 45d9a23（2026-09-21）未改，布局与协议 V3.0 §2.4 一致。
- `MowerZonesPage` 没有跟随：`_zones` 只在进页时从 `MowerDevice.zones` 拷贝一次，既不监听 `MowerDevice`，也不在进页时现读 SDK。停留在页面上时机器改了区域 2，页面不变；下发后被设备拒绝、5 秒回弹到设备快照时，页面同样不变。该页自 ddced32 起一直如此，并非近期改动引入。
- 「旧版正常」在代码里没有找到对应差异（上报链路 `_listenForDeviceUpdates` → `mowerReports` → `_syncFromDevice` 近期未改），未能确认旧版具体是哪一版、在什么操作顺序下表现正常。
- 雨淋设置、时间同步页是同样的「进页拷贝一次」写法，本次未改。

## 改动

- `mower_device.dart`：新增 `rereadDps(state, dps)`——从 SDK 当前设备模型（`state.mowerDps`）现读指定 DP；读取期间到达的更新实时上报优先（沿用 `_snapshotSequence` / `_appliedDpReads`），还在等下发回显的 DP 跳过，读完 `notifyListeners`。
- `mower_zones_page.dart`：`initState` 同时取 `_zones` 与 `_synced`（页面最近一次采用的设备值签名，不能惰性初始化），监听 `MowerDevice`；进页后 `rereadDps([DP103])`。设备区域配置变化（上报、现读、回弹）时：页面没有未保存修改 → 刷新并记联调日志；用户已拖动 / 改过还没保存 → 保留用户修改，只记日志。`dispose` 取消监听。保存后 `setZones` 的通知与本地一致，不触发刷新。
- 测试 `mower_pages_test.dart` 新增两例：进页现读拿到绑定后才变的区域 2、停留时上报 DP103 刷新区域 2；用户已改未保存时上报不冲掉修改。

## 决定

- 有未保存修改时保留用户修改：保存是 5 区全量替换，用户确认保存时会以页面值覆盖设备；若需要「上报一律覆盖页面」可再改。

## 验证

本机无 Flutter / Dart，analyze、format、测试、编译均未运行；未真机。`git diff --check` 通过。需本地执行：

```bash
dart format lib test
flutter analyze
flutter test test/features/mower/mower_pages_test.dart
```

真机：进区域设置页停留，在机器上改区域 2，页面应随即刷新；联调日志出现「上报 ← 割草机-区域设置 DP103=…，页面已刷新」。若页面仍不变且日志里没有 DP103 上报，说明设备本地修改没有上报 DP103，需固件确认。

## 未决

- 旧版正常的具体版本与操作顺序未确认。
- 雨淋设置、时间同步页同样不跟随上报，是否一并改待定。

## 回滚

还原对应提交即可。
