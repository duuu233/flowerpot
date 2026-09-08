# 设备图库改按 deviceId 取数，配网与首页文案清理

> 文档类型：Historical Change Record
> 日期：2026-09-08
> 环境：SSH 开发机（无 Flutter/Dart 工具链）
> 分支与起始版本：main / 9dfc52d
> 范围：`lib/src/core/backend/`、`lib/src/state.dart`、配网搜索/选择页、定制动画页、首页概览与空态、对应测试
> 当前权威文档：`AI_CONTEXT.md`、`docs/API_对接核对_2026-09-04.md`

## 背景与目标

1. 图库页报「图片列表加载失败：服务器暂时不可用，请稍后重试（HTTP 404）」。排查结论：这句是 `ApiClient._parse` 对非 2xx 的兜底，落点是 `AnimationsPage._refreshFiles`；进图库要先走 `_ensureBackendDevice`（`getUserProductList` →（必要时）`getUserProductDetail` →（未绑定时）`Product/getProductList` + `addUserProduct`）换后端 `userProductId`，再调 `getUserProductImgList`，这条链路上任何一个接口 404 都会把整页顶掉。产品口径：设备档案由涂鸦提供，图库只调「用户产品图片列表」这一个接口即可。
2. 配网与首页的一批文案/功能按产品要求下线，另修首页四张指标卡的错位。

## 变更内容

### 图库只调一个后端接口

- `AppBackendRepository.getImages` / `uploadImage` 的入参由 `int userProductId` 改为 `String deviceId`；`HttpAppBackendRepository` 相应改为 `getUserProductImgList?pageIndex=1&pageSize=100&deviceId=…` 与 `setUserProductUpload?deviceId=…`。
- `FlowerpotState._refreshBackendImages(deviceId)` 直接向后端要图，`refreshAnimations` / `addAnimation` 不再调用 `_ensureBackendDevice`；会话缺失时的报错抽成 `_requireBackendSession()`，与原来 `_ensureBackendDevice` 的文案一致。
- `_ensureBackendDevice` 及 `getUserProductList` / `getUserProductDetail` / `addUserProduct` / `Product/getProductList` 仍保留给纪念日链路（本轮未动）。

### 配网与页面文案

- 搜索设备页：删除「扫描到 N 个网络…」「手机当前连接：…」「设备热点已经出现在 Wi-Fi 列表里的话，用下面的手动选择。」以及「从附近网络中手动选择设备」按钮与 `_pickManually`；未发现时只保留「请长按设备按键让它进入配网状态后重新扫描。」和「重新扫描 / 设备已在配网状态，继续」。
- 搜索设备页新增 45 秒搜索窗口（`DeviceSearchPage.searchWindow`，重扫间隔 2 秒）：窗口内页面一直显示「搜索中」并反复扫描，扫到设备热点立即进选择页；Wi-Fi 未开、无权限这类不可重试的失败立刻报出，不空等。
- 选择设备页：删除「设备不在上面？显示附近全部网络」（含 `_showAllNetworks` 展开逻辑）与两处「设备已在配网状态，继续」；未识别到热点时仍直接列出原始扫描结果，`_connect` 收窄为必须选中某个网络。
- 首页空态文案「还没有连接智能花盆…」改为「还没有连接智能设备…」。
- 定制动画页：删除「文件同步」按钮与 `_syncFiles`（连带删除已无调用方的 `FlowerpotState.syncAnimations`），删除「仅支持屏幕录制或本地文件。点击这里重新授权」权限提示条，提示语「支持屏幕录制文件或本地文件上传」改为「支持本地图片文件上传」。

### 首页指标卡对齐

`HomePlantOverview` 下排两张卡片原来是 `top: 145, left: 2` 与 `top: 154, right: 0`，与上排不同边、彼此不同高；统一为 `top: 145` + `left/right: 0`，四张卡片同宽同高、上下左右对齐。

## 关键决策

- **「要连接至设备吗？智能花盆将使用临时 WAN 网络连接至设备。」这个弹框没有动**：它不是 App 的对话框，源码里没有这两句。它是 Android 10+ 对 `WifiNetworkSpecifier` + `ConnectivityManager.requestNetwork` 的系统授权框（`MainActivity.joinDeviceHotspot`），必须由用户点同意，应用侧无法预先接受或跳过。要去掉它只能改用「引导用户去系统设置连热点」的手动路径，那是更多步骤而不是更少。
- 图片列表改按 `deviceId` 过滤，依赖后端该接口支持这个参数（本轮无法对真实服务验证）。若后端只认 `userProductId`，请求会退化成「按 token 拉全部」或返回空列表，需要后端确认。
- 搜索窗口取 45 秒、间隔 2 秒：原生一次 `scanWifi` 最多等 5 秒（被系统限流时直接回缓存），一轮窗口大约能扫六七次。

## 外部操作

无。未部署、未联调、未改远端配置。

## 验证结果

- **本机没有 Flutter/Dart 工具链，`flutter analyze` 与 `flutter test` 都没跑**，本轮只做静态复核与测试用例同步修改，不宣称通过。
- 同步修改的测试：`test/core/backend/app_backend_repository_test.dart`（新增图库按 `deviceId` 取数的契约用例）、`test/state_backend_integration_test.dart`（假后端改新签名，并断言 userProduct 那几个接口不再被调用）、`device_search_page_test.dart`（删手动选择用例、新增 45 秒窗口内重扫用例、失败态用例改为跑满窗口）、`device_selection_page_test.dart`、`animations_page_test.dart`、`home_empty_device_content_test.dart`。
- 45 秒窗口的用例依赖 `tester.pump(Duration)` 推进假时钟，需在有 SDK 的机器上实跑确认没有遗留 Timer。

## 未完成项与风险

1. 全套测试与静态分析待在有 Flutter SDK 的机器上补跑。
2. `getUserProductImgList` / `setUserProductUpload` 是否支持 `deviceId` 过滤需要后端确认；404 的根因（路由缺失还是临时地址 `120.25.227.36:8601` 部署问题）也仍待服务端核实。
3. 搜索页去掉手动选择后，热点名不在白名单、系统又扫不出的情况下只能走「设备已在配网状态，继续」。
4. 首页四卡对齐只按源码坐标核对，未在真机/模拟器截图比对。

## 回滚或恢复

全部改动集中在上述文件，`git revert` 对应提交即可回到旧行为；后端接口若不支持 `deviceId`，只需把 `getImages`/`uploadImage` 的入参与 query 换回 `userProductId` 并恢复 `_ensureBackendDevice` 调用。
