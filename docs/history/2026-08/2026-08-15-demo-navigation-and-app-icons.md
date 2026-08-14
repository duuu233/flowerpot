# 演示导航改造与 iOS/Android 应用图标生成

> 文档类型：Historical Change Record
> 日期：2026-08-15
> 环境：SSH（无 Flutter/Dart SDK、无 Pillow/ImageMagick）
> 分支与起始版本：main / fef6542
> 范围：`lib/src/`、`test/`、`ios/Runner/Assets.xcassets`、`android/app/src/main/res`、`tool/`
> 当前权威文档：`docs/TEMP_STATIC_PAGE_PREVIEW.md`

## 背景与目标

项目当前是纯静态页面，需要交给他人演示整体 UI。要求：补底部菜单、去掉页面调试目录、
默认进登录页、把填 Wi-Fi 挪到连接设备之后、调整连接成功页按钮、交换设备列表页与设备详情页
左上角的入口，并让设备列表先进入未添加植物页。同时按兄弟项目 `../flutter` 的图标要求，
用新 LOGO 生成 iOS/Android 全套应用图标。

## 变更内容

导航与页面：

- 新增底部菜单：`AppShell` 改为 `IndexedStack` + `AppBottomNavigation`，Tab 为「首页 / 我的」。
  首页 Tab 在无设备时显示 `HomeEmptyDeviceContent`，有设备时显示 `DeviceListPage`。
- 删除 `preview_hub_page.dart` 与 `preview_return_overlay.dart`；`app_routes.dart` 去掉目录入口、
  鉴权旁路和返回目录悬浮层，根路由恢复 `authenticated ? AppShell : AuthPage`。
- `flowerpot_app.dart` 不再启动即 `enterDemo()`；`StaticPreviewConfig.enabled` 改为只控制
  Mock 后端是否预置演示设备（`TuyaRepository.create(seedMockDevice:)` →
  `MockTuyaRepository(seedDevice:)`），因此登录后落在「登录后无设备」。
- 配网顺序改为 搜索设备 → 选择设备 → 连接 Wi-Fi → 连接成功。`DeviceSearchPage` 无凭据也自动前进；
  `DeviceSelectionPage` 连接后跳 Wi-Fi 页并带上 `PairingArguments`；实际配网移到 `PairingPage`。
- 连接成功页去掉「添加植物」，「返回首页」改为「已完成」。
- `DeviceListPage` 左上角由返回按钮改为个人中心入口（在 Shell 内切换 Tab，独立路由时跳 `/mine`）；
  `HomeHeader` 新增 `onBack`，被 push 的设备页显示返回按钮而非头像。
- 新增 `deviceHome` 路由与 `HomeDeviceArguments`：设备列表点击先进未添加植物页，
  选择植物后 `pushNamedAndRemoveUntil` 到详情页，返回直接回到设备列表。
- `FlowerpotState` 新增 `_plantedDevices` / `hasPlant()`：`SmartPlanterDevice.plant` 非空，
  无法从设备本身判断「未添加植物」，改由本次会话是否确认过选择来决定。
- 抽出 `lib/src/shared/user_avatar.dart` 的 `resolveUserAvatar()`，供首页与设备列表共用。

应用图标：

- 新增 `tool/generate_app_icons.py`：本机无 Pillow/ImageMagick，脚本自带 PNG 解码、
  Lanczos3 重采样与编码，从 `assets/微信图片_20260814224541_891_12.png` 生成全套图标。
- iOS：重写 `AppIcon.appiconset` 全部 15 个尺寸，统一输出无 alpha 的 RGB。
- Android：重写五档密度 `ic_launcher.png`，新增五档 `ic_launcher_foreground.png`、
  `mipmap-anydpi-v26/ic_launcher.xml`（白底 + 前景 inset 30%）与
  `values/ic_launcher_background.xml`（`#FFFFFF`）。

## 关键决策

- 底部菜单定为「首页 / 我的」两个 Tab（用户确认）。设备列表页左上角的个人中心入口保留，
  在 Shell 内切换 Tab 而不是再 push 一层 `MinePage`。
- 图标沿用兄弟项目 `../flutter` `docs/runbooks/BUILD_RELEASE.md` 第五条的规则：
  自适应图标白底、前景 inset 30%、1024 图标去 alpha。不使用品牌色底。
- `StaticPreviewConfig` 保留但重新定义职责，避免演示开关继续影响启动入口与鉴权分流。
- `enterDemo()` 增加 `seedDevice` 参数，使登录页的「体验模式」与正常登录落在同一状态。

## 外部操作

无。未安装 SDK，未构建 APK/IPA，未上传商店素材。

## 验证结果

- `python3 tool/generate_app_icons.py` 执行成功，逐个核对输出尺寸与色彩类型：
  iOS 15 个文件全部为 `8-bit/color RGB`（无 alpha），Android `ic_launcher.png` 为 RGB、
  `ic_launcher_foreground.png` 为 RGBA。1024 图标已用图像预览确认构图正确。
- 源图仅 186×186，放大到 1024 明显偏软。脚本会打印该提示。
- **未运行 `dart format`、`flutter analyze`、`flutter test`**：本机没有 Flutter/Dart SDK。
  已人工核对改动文件的括号配平与 80 列宽度，并同步更新受影响的测试，但静态检查与测试
  必须在有 SDK 的环境补跑。

## 未完成项与风险

- 待补跑：`dart format lib test`、`flutter analyze`、`flutter test`。
- 待替换：换 1024×1024 或更高分辨率的 LOGO 原图后重跑 `tool/generate_app_icons.py`，
  否则 App Store 图标清晰度不达标。
- 未处理：`web/icons/`、`web/favicon.png` 仍是 Flutter 默认图标（本次只要求 iOS/Android）。
- `PairingSuccessPage.deviceId` 目前未被页面使用，仅保留路由契约。

## 回滚或恢复

- 图标：`git checkout -- ios/Runner/Assets.xcassets/AppIcon.appiconset android/app/src/main/res`
  并删除未跟踪的 `mipmap-anydpi-v26/`、`ic_launcher_foreground.png`、`values/ic_launcher_background.xml`。
- 导航：整组改动集中在上述文件，可整体回退到 fef6542。演示开关本身改为 `enabled = false`
  只会恢复预置设备，不会恢复已删除的调试目录。
