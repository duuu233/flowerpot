# 应用名改为「东方金穗」，页面文案 YSplanter 改为东方金穗

> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：b95cb6a
> 当前规则：`docs/history/other/PRODUCT_RULES.md` §4.27

## 需求

1. App 名称「智能花盆」改为「东方金穗」。
2. App 内页面上展示的 YSplanter 文字改为「东方金穗」；包名和配置类名称不动。

## 改动

- 应用名：`android/app/src/main/AndroidManifest.xml` `android:label`；`ios/Runner/Info.plist` `CFBundleDisplayName`、`CFBundleName`；`lib/src/app/flowerpot_app.dart` `MaterialApp.title`。
- 页面文案：关于页标题与「我的」菜单「关于东方金穗」、关于页应用名；行为（午休 / 夜间作息）、触摸、听觉、显示、LED、振动设置说明；首页帮助话题两条；登录密码说明；隐私政策 / 用户协议标题与开头三处；植物自动检测说明（中、英）。
- 读屏标签：设备占位图、未种植物设备图、登录页品牌图标、关于页应用图标。
- 注释中「关于YSplanter」的引用同步；测试中对应文案断言同步（13 个测试文件）。

## 有意不改

- YSplanter 字标图片 `assets/images/ysplanter_wordmark.png`（启动页、登录页、首页顶栏、关于页）：图片内容是英文字标，换成「东方金穗」需新图或改成文字，待产品决定；启动页、登录页、首页顶栏字标的读屏标签保持 YSplanter，与图片一致；关于页字标读屏取应用名，随之为东方金穗。
- 「智能花盆」作为设备品类的说法：iOS 蓝牙 / 本地网络权限说明、隐私政策与用户协议正文、后端无产品名时的兜底名。
- 包名 / Bundle ID、涂鸦配置、热点前缀 `ysplanter`、资源与类名、测试里的设备名 YSplanter-01。

## 验证

本机无 Flutter，测试、分析与构建未运行，未真机。需运行 `flutter test` 与 `flutter analyze`，并在真机确认桌面名称与上述页面文案、换行。部分说明按设计稿逐行拆分，「东方金穗」比 YSplanter 略短，换行位置需目视确认。

## 回滚

撤销本提交即可。
