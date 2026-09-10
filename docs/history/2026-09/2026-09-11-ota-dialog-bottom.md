# 2026-09-11 OTA 升级弹框改为贴底

## 要求

产品：「OTA升级的弹框底部定位就行不要在中间」。

## 改了**两个**弹框，不是一个

升级动线上有两个弹框，原来都是居中的：

| 弹框 | key | 位置 |
| --- | --- | --- |
| 「检查更新 / 当前版本 / 发现新版本 / 稍后·立即更新」 | `firmware-update-dialog` | `device_other_settings_page.dart` |
| 升级进度（进度条 + 百分比 + 知道了） | `ota-progress-dialog` | `widgets/ota_progress_dialog.dart` |

**只改后面那个不行**——点完「立即更新」画面会从居中跳到底部，比两个都居中更难看。

## 只改位置，不动样式

两处都是加两行：

```dart
alignment: Alignment.bottomCenter,
insetPadding: EdgeInsets.fromLTRB(
  <原来的左右留边>, 24, <原来的左右留边>,
  MediaQuery.viewPaddingOf(context).bottom + 16,
),
```

底边**不写死**：全屏手势导航的机型底部有一条 home indicator，贴着画会被压住，所以按
`viewPadding.bottom` 再加 16。左右留边沿用各自原值（「检查更新」是 24，进度层是 Flutter
默认的 40），圆角、背景、`maxWidth: 327` 一律没动。

## 踩过的弯路（自己的）

第一版我把进度层改成了 `showModalBottomSheet` —— 那会把卡片拉成**满宽**、顶部切成两个直角，
还得自己补拖拽横条、`isDismissible: false`、`enableDrag: false` 一堆东西。产品说的是"换个
位置"，不是"重做成底部抽屉"。已回退成 `AlertDialog` + `alignment`。

⇒ 写进 `PRODUCT_RULES` §4.2：**不要改成 `showModalBottomSheet`。**

## 未动的两个弹框

- **APP 版本更新**（`app_update_dialog.dart`）：那是应用自身升级，不是固件 OTA，保持居中。
  产品要一起改的话一行 `alignment` 就行。
- **设置项选择表单**（`_showSettingsChoiceSheet`）：本来就是底部升起的。

## 验证

**未验证**（本机无 Flutter 工具链）。静态检查：两个文件括号配平；`AlertDialog.alignment` /
`Dialog.alignment` 都是 Flutter 自带参数，没引入新依赖；四个 key
（`ota-progress-dialog` / `-bar` / `-percent` / `-close`）和
`firmware-update-dialog` / `postpone-firmware-update` / `install-firmware-update` 全部保留。
