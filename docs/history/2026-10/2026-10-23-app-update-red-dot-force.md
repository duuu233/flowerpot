# App 升级红点与强制升级补全

> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：dc7159f
> 当前规则：`docs/history/other/PRODUCT_RULES.md` §4.28

## 需求

检测 App 升级功能是否完整：①普通升级要在升级入口显示红点；②强制升级功能是否完整。后台升级配置与同一后台的其它 App 一致（`/Client/Basic/getLastVersion`）。

## 检测结论（修改前）

| 项 | 现状 | 问题 |
| --- | --- | --- |
| 「我的 → 关于东方金穗」红点 | 状态 `hasAppUpdate` 正确传到菜单，但 `MineMenuList` 把 `badge` 画成「复制」图标（2026-09-09 改意见反馈行尾时把条件写错） | 有新版本时显示复制图标、不显示红点；意见反馈反而没有复制图标 |
| 关于页「检查更新」 | 只把文字换成「发现新版本 Vx」 | 无红点 |
| 本机版本号 | `AboutPageModel.current()` 写死 `1.0.0` | 发新版后，装了新包的用户仍报 1.0.0：一直被判有新版本，强制升级弹窗永远关不掉 |
| 强制升级弹窗 | 启动时 `isUpdate`+`compulsory==1` 弹，返回键/遮罩关不掉 | 「立即更新」只复制下载链接；后台没配下载地址时弹窗关不掉、按钮也无效，用户卡死 |
| 启动检测、字段解析 | `AppShell` 首帧查一次；字段按 swagger 解析 | 无问题 |

## 改动

- `lib/src/core/config/app_build_info.dart`（新增）：`package_info_plus` 读安装包版本号；`main()` 在 `runApp` 前读。`AboutPageModel.current()` 改用它，读不到显示 `--`；`FlowerpotState.checkAppVersion` 版本号为空时不查。
- `mine_menu_list.dart`：`badge` 行画红点 + 箭头；意见反馈有邮箱时恢复复制图标。
- `about_page_model.dart` / `about_page.dart` / `about_version_card.dart`：新增 `hasUpdate`，「检查更新」行状态文字前点红点。
- `app_update_dialog.dart`：「立即更新」用 `url_launcher` 外部打开下载地址（只放行 https、market、itms-apps），打不开给提示；强制升级不关弹窗。
- `shell_page.dart` / `about_page.dart`：没配下载地址时不按强制弹。
- `pubspec.yaml`：新增 `package_info_plus ^10.2.1`、`url_launcher ^6.3.0`（`pubspec.lock` 未更新，需在有 Flutter 的环境 `flutter pub get` 后提交）；`AndroidManifest.xml` `<queries>` 增加 https VIEW。
- 测试：`flutter_test_config` 固定 `AppBuildInfo.version = '1.0.0'`；`mine_page_test` 新增红点/复制图标用例；`about_page_test` 新增检查更新红点用例。

## 未改 / 待定

- 后台没配下载地址时不回退调 `getAndroidDownload`：该接口返回结构未核实，且 iOS 不适用。
- `lib/src/features/profile/presentation/app_settings_page.dart` 里的「App 升级」行是未接入路由的旧页面，未动。
- 弹窗文案仍为中文。

## 同日追加：「不提示升级」不点红点

用户确认「“不提示”的意思是连红点也不要」。`BackendAppVersion` 新增 `silent`（`compulsory == 4`）与 `showsBadge`（有新版本且非 silent）；「我的」菜单取 `FlowerpotState.showAppUpdateBadge`，关于页「检查更新」红点取 `showsBadge`，状态文字与点击弹框不变；`hasAppUpdate` / 强制判定不变。新增 `app_backend_repository_test` 用例覆盖 compulsory 1–4 的解析。

## 验证

本机无 Flutter，`flutter pub get`、`flutter analyze`、`flutter test` 与构建均未运行，未真机。需在有工具链的环境：`flutter pub get`（并提交更新后的 `pubspec.lock`）、`flutter analyze`、`flutter test`；iOS 需 `pod install`。真机验收：后台配置比当前高的版本，分别以 `compulsory`=1/2 验证启动弹框、红点、立即更新跳转（Android 浏览器下载、iOS App Store）、装新包后不再提示。

## 回滚

撤销本提交即可；依赖与清单改动一并撤回。
