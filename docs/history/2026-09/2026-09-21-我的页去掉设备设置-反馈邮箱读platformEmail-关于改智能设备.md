# 「我的」页去掉设备设置、意见反馈读后台平台邮箱、关于页改「智能设备」

> 文档类型：Historical Change Record
> 日期：2026-09-21
> 环境：SSH（本机无 Flutter / Dart 工具链）
> 分支与起始版本：main / `45d9a23`
> 范围：`lib/src/features/profile/`、`lib/src/core/backend/backend_models.dart`、`lib/src/state.dart`、
> `lib/src/features/splash/presentation/splash_page.dart`、`test/`
> 当前权威文档：`docs/PRODUCT_RULES.md` §4.9；`AI_CONTEXT.md`「我的与关于」；`docs/UI/MINE_PAGE_IMPLEMENTATION.md`

## 背景与目标

产品：「我的页面：1，去掉设备设置 2，意见反馈要读取后台配置的邮箱，3，关于 点击去 去掉 智能花盆的文字改为智能设备
（LOGO 保留）」。

## 核查

| # | 问题 | 原因 |
| --- | --- | --- |
| 1 | 「我的」页有「设备设置」 | 当初为「刚配网还没选植物时够不到解绑」加的备用入口；现在设备列表就是首页，每台设备自己的页面都能进设置 |
| 2 | 意见反馈那一行一直没有邮箱 | `BackendBasicData.contact` 只认 `serviceEmail` / `contactEmail` / `email` / `servicePhone` / `contact` 这几个猜的键名；按 swagger（`BasicDataApiOut`），`/Client/Basic/getBasicData` 实际返回的是 **`platformEmail`**（「平台邮箱」），一个都对不上 |
| 3 | 后台改了邮箱，App 要重启才看得到 | `loadBasicData()` 拉到一次就整个会话复用 |
| 4 | 关于页标语「您的智能花盆贴心伴侣」 | `AboutPageModel.current()` 写死 |

后台（`flowerpot-web` 的「系统设置」）是通用的 configKey / configValue 列表，邮箱是数据，App 只需要读对字段。

## 变更内容

1. **去掉「设备设置」**：`MineMenuKind.deviceSettings`、菜单项、图标分支、`_openDeviceSettings` 删除；菜单剩六项。
   `AppAssets.deviceSettingsIcon` 保留（首页快捷列表还在用）。
   为它加的 `FlowerpotState.selectedPlanter`（09-21 割草机那轮，防止把割草机带进花盆设置页）随之没有调用方，删除，
   `mower_live_test.dart` 里对应的一条用例一起删。
2. **意见反馈读 `platformEmail`**：`BackendBasicData.platformEmail`（先认 `platformEmail`，没有再退回原来的
   `contact` 那几个键）；「我的」页 `feedbackEmail: state.basicData.platformEmail`。后台没配仍是不显示、点击提示
   「后台还没有配置平台邮箱」，App 不写死兜底。
3. **每次进「我的」页都重拉**：`loadBasicData({bool refresh = false})`，「我的」页进页和「网络异常」重试都带
   `refresh: true`；拉失败保留旧的那份。协议页、搜索页仍用默认的复用。
4. **关于页**：标语改「您的智能设备贴心伴侣」，Logo 与 YSplanter 字标不动；`releaseNotes` 第一条同步改为
   「新增智能设备连接与管理能力」（页面上目前不渲染）。启动页里被 `_showBranding` 关着的同一句标语一起改，免得以后
   打开时又冒出「智能花盆」。
5. **用例**：
   - `mine_page_test.dart` 加 1 条：菜单正好六项、没有「设备设置」，反馈邮箱去空白后带上，空白视为没配；
   - 新增 `test/state_basic_data_refresh_test.dart` 2 条：默认复用 / refresh 重拉且邮箱跟着变；refresh 失败保留旧值；
   - `app_backend_repository_test.dart` 断言 `data.platformEmail`；
   - `about_page_test.dart` / `splash_page_test.dart` 改新标语，关于页再断言不含「智能花盆」。

## 关键决策

- **`platformEmail` 优先、`contact` 那几个键兜底**，不写死邮箱：产品原话是「读取后台配置的邮箱」，后台没配就该空着。
- **只在「我的」页强制重拉**：基础数据还有协议正文等大字段，别的页面没必要每次拉；「我的」页一次请求的代价可以接受。
- **只改「关于」这一处的「智能花盆」**：MaterialApp `title`（安卓最近任务里显示）、协议正文、帮助中心等其它地方的
  「智能花盆」不在本次要求里，没动。

## 外部操作

只读：查了 `https://api.yikaltd.com/v2/api-docs` 里 `BasicDataApiOut` 的字段定义。没有调用业务接口。

## 验证结果

- 四个 Dart 静态自检（331 个文件）全绿；改动的 13 个 Dart 文件剥掉字符串与注释后括号配平；
  `MineMenuKind.deviceSettings` / `selectedPlanter` 全仓已无引用；新 / 改用例都在 `main()` 里。
- **未跑** `dart analyze` / `flutter test` / 编译：本机无工具链。新增 3 条用例没执行过。
- **未真机验证**：要看后台「系统设置」里平台邮箱确实有值、`getBasicData` 返回里带着 `platformEmail`。

## 未完成项与风险

1. 后台若平台邮箱没配，「我的」页意见反馈那一行仍是空的——这是预期行为，不是 bug。
2. MaterialApp `title: '智能花盆'` 等其它「智能花盆」字样未改，产品若要全 App 统一需另提。

## 回滚或恢复

`git revert` 本轮提交即可；无数据迁移。
