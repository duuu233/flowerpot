# 花盆首页快捷入口：隐藏自定义图片，放上选择植物

> 文档类型：Historical Change Record
> 日期：2026-11-04；环境：远程 SSH 服务器
> 分支与起始版本：main / 38253f3

## 依据与范围

产品要求：① 首页隐藏「自定义图片」（原「定制动画」）入口，App 暂时不做这个入口；② 把植物选择放到这个位置，图标做适配。

## 改动

- `home_dashboard_model.dart`：`HomeActionKind` 新增 `plant`；首页快捷列表第一项由「自定义图片」换成「选择植物」，顺序为 选择植物 → 帮助中心 → 设置。`animation` 枚举、`AnimationsPage` 与 `AppRoutes.animations` 保留，恢复入口时把那一项加回 `actions` 即可。
- `home_page.dart`：新增 `_openPlantPicker`，与设备设置页「选择植物」同一套门禁和页面：没设备提示「请先添加并连接花盆」、离线走 `ensureDeviceOnline`、盆里没有植物（DP 116 == -1）提示 `HomeCareBanner.plantMissingNotice` 不进页，否则 `PlantPickerPage`（`PlantPickerMode.select`）。
- 图标：新增 `assets/images/home_plant_select_icon.png`（`AppAssets.homePlantSelectIcon`，80 × 80 二倍图）。底板与另外三张首页图标一致（`#EEF6F7` 圆角底，逐像素取自 `device_settings_icon.png`），图形取 `select_plant_icon.png` 的盆栽，改成首页图标同一种青色 `#70AFB5`，按 4/3 双线性放大到与另外三张一样的 40px 见方、居中（图形范围 x 20–59 / y 19–59，与其余三张 19~60 一致）。没有更高清的盆栽源图，放大后边缘略软。
- `home_quick_actions.dart`：`plant` 用新图标。

## 测试

- `test/features/home/home_scene_test.dart`：原用例「帮助中心排在电池状态下方」自 2026-09-15（3a7e48a 电池状态挪进设置页）起引用已删除的 `HomeActionKind.battery`，整个文件编译不过；按当前顺序改写为「选择植物在第一位，不显示自定义图片」。
- `test/widget_test.dart`：首页断言改为不显示「自定义图片」、显示「选择植物」。

## 验证

本机没有 Flutter / Dart，未运行 `flutter analyze` / `flutter test`，未编译、未真机。新图标只在本机按像素核对了底板、颜色与图形范围。本地需跑：`flutter analyze`、`flutter test test/features/home/home_scene_test.dart test/widget_test.dart`，并真机看首页图标与另外三张是否协调。

## 回滚

`actions` 第一项改回 `HomeActionData(kind: HomeActionKind.animation, label: '自定义图片')`，两个测试的断言随之改回；新图标与 `plant` 分支可保留不用。
