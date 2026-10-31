# 花盆自定义图片改名、提示两条与 DP169 首次校准门禁

> 文档类型：Historical Change Record
> 日期：2026-10-31；环境：远程 SSH 服务器
> 分支与起始版本：main / 1f85033

## 依据与范围

产品 2026-10-31 口径：

1. 「定制动画」统一改称「自定义图片」；
2. 自定义图片页提示列表在「长按文件可删除已选文件」下方新增「设备中间按键可长按退出和进入」「左右触摸可以切换自定义图片」；
3. DP169 `first_calib`（bool rw，默认 false）：首用 / 恢复出厂配网成功 → 设备教程结束 → 自动水位校准；完成、跳过、退出界面任一发生即上报 true，恢复出厂清回 false；为 true 时 App 才能进设备页（产品确认拦整个设备页，不只水位校准页）；
4. SD 卡更新类型：表情动画 .mjpeg、植物映射 .json、节日素材 .mjpeg。App 无对应界面，产品确认 App 不改，只写进报告。

## 改动

- `tuya_config.dart`：登记 `first_calib: 169`；09-28 说明里 169 `file_download` 作废（App 从未接入）。
- `tuya_models.dart`：`SmartPlanterDevice.firstCalibrated`，构造默认 true（只给 Mock / 静态预览），`copyWith` 带上。
- `tuya_repository.dart`：`firstCalibrated: boolean(dp('first_calib'), false)`；DP 推送会重新解析合并后的快照，169 变 true 后列表里的设备随之更新。
- `device_list_page.dart`：`_openDevice` 在离线、割草机判断之后，花盆 `firstCalibrated` 为 false 时提示 `deviceFirstCalibrationPendingMessage`（「请先在设备上完成使用教程与水位校准」）并留在列表。设备页另一入口植物选择页本身就在设备页里面，不另加门禁。
- `animations_page.dart`：标题改「自定义图片」；提示卡加两条，文案区高 126 → 176。
- `home_dashboard_model.dart` 首页入口、`interaction_log_overlay.dart` 路由名、`state.dart` 两条联调日志前缀同步改名。注释与设计稿文件名（`定制动画.png` 等）不改。
- 测试：`tuya_config_test.dart` DP 表加 169；新增 `test/tuya/first_calib_dp_test.dart`（没报 / false / true / "true"）；`device_list_page_test.dart` 新增未完成校准不进设备页；`animations_page_test.dart`、`widget_test.dart` 改名与新提示断言。

## 决定

- 没上报 DP169 一律按 false：按产品口径「为 true 时可进」，旧固件（不带 169）因此进不了设备页，需固件带上 169。
- 只拦进入：已在设备页时 169 变回 false（只有恢复出厂会这样，而恢复出厂会解绑）不把用户踢出。
- 提示页说明「请上传符合要求的文件以确保动画可以正常播放。」未在本次范围内，没改。

## 验证

本机无 Flutter / Dart，analyze、format、测试、编译均未运行；未真机，未用带 DP169 的固件联调。`git diff --check` 通过。需本地执行 `flutter analyze` 与 `flutter test test/tuya/ test/tuya_config_test.dart test/features/devices/ test/widget_test.dart`。

## 未决

- 平台功能点需新增 / 改为 169 `first_calib`（bool），固件需在教程与校准结束后上报。

## 回滚

还原对应提交即可。
