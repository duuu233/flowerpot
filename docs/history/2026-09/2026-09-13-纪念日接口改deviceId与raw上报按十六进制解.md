# 纪念日接口 404 与需水状态报表解不出数据

> 文档类型：Historical Change Record
> 日期：2026-09-13
> 环境：SSH 开发机 `/pgdata/pg/dh/flowerpot`
> 分支与起始版本：`main` / `ce8d051`
> 范围：APP 后端纪念日接口、raw 功能点上报解码（131–139、154、158/159）、需水状态曲线
> 当前权威文档：`AI_CONTEXT.md` §9、`docs/TUYA_SDK_SETUP.md`

## 背景与目标

产品反馈两件事：

1. 纪念日新增 / 编辑报 404。给的入参是 `ClientProductAnniversaryAddApiIn`：
   `anniversaryDate`、`anniversaryId`（编辑时）、`content`、`contentType`、`deviceId`（涂鸦设备 id）、
   `title`，`device` / `language` / `terminal` / `userToken` 走 headers。
2. 需水状态页报表没数据，但联调日志里「有数据」；智能生活 APP 上能看到多条水位均值、
   多条土壤湿度均值，光照一直是 0。

## 结论

### 1. 纪念日 404：卡在保存的第一步，不在纪念日接口本身

- 拉 `https://api.yikaltd.com/v2/api-docs` 核对：纪念日 6 个接口的路径都在。不带 token 调这几个路径
  回 `retCode 406 请重新登录`，说明接口存在；随便编一个不存在的路径回 HTTP 500。
- **真正打出 404 的是前置步骤**：`FlowerpotState._saveMemorialOnBackend` / `refreshMemorials` 先调
  `_ensureBackendDevice` 用涂鸦 deviceId 去换后端的 `userProductId`，依次用到
  `getUserProductList` → `getUserProductDetail` → `getProductList` → `addUserProduct`。
  **这四个接口连同 `editUserProduct` / `delUserProduct` 已经从 swagger 里整体下线。**
  App 用到的 34 条路径逐条对照 swagger，缺的正好是这 6 条。
  2026-09-08 图库就因为同一条链路 404 改成了直接按 `deviceId` 走（`getImages` 的注释写着），
  纪念日当时没跟着改。
- 新契约里纪念日本来就不要 `userProductId`：新增 / 编辑的 body 是 `deviceId`，列表返回行里也是
  `deviceId`。旧代码 body 里发的是 `userProductId`，即便前置步骤能过，后端也拿不到设备。

### 2. 报表没数据：SDK 交上来的 raw 值是十六进制，App 按 base64 解

- 解包涂鸦 Android SDK 7.5.1 的 `thingsmart-device`（字节码调用序列，见「外部操作」）：
  - `DevUtil.decodeRaw(Map, Map)`：对 schema 类型为 raw 的 DP 执行
    `String.getBytes` → `android.util.Base64.decode` → `HexUtil.bytesToHexString` → `Entry.setValue`。
    本地 / MQTT 上报等多条接收路径都会调它，所以 `onDpUpdate` 和 `DeviceBean.getDps()` 里的 raw 值
    **已经是十六进制串**。
  - `DevUtil.encodeRaw`：`HexUtil.hexStringToBytes` → `Base64.encodeBase64`——下发时 App 写十六进制
    是对的（`TuyaMemorialCodec.encodeRaw` 一直这么写）。
- 以前的注释「上报是 base64、下发是 hex，两个方向真的不一样」**是错的**。在 App 这一侧两个方向都是 hex。
- 按 base64 解十六进制串的后果（十六进制字符全在 base64 字母表里，不会报「非法字符」）：
  - 包长为奇数字节 → 十六进制长度 ≡ 2 (mod 4) → Dart `base64.decode` 抛
    `Invalid length, must be multiple of four`（已对照 Dart SDK `convert/base64.dart` 源码）→ 解码器返回空
    → 页面「暂无历史数据」。日包 3+96=99 字节、水位/土壤周包 4+7=11、月包 4+31=35、光照日包 3+192=195
    **全在这一类**。
  - 包长为偶数字节（光照周包 4+14=18、月包 4+62=66）→ 解出一串乱码当曲线画。
  - 158/159 固定日期 8 字节 ASCII → 16 个十六进制字符 → 解出 12 个乱码字节 → 生日 / 结婚纪念日读成「未设置」。
  - 联调日志只打「原始字符数 / 解出点数」，所以看起来是「有数据」（例如 `198字符/0点`）。
- 顺带发现水位曲线纵轴上限沿用图表默认的 100，而 131–133 与 DP 105 的量程是 0–200 mL，超过 100 mL
  的点会被压在顶线上。

### 3. 光照一直是 0

智能生活 APP 看到的也是 0，App 端不改数据；这是固件 / 传感器侧的问题，需要设备方确认 137–139 与
DP 109 是否真的在采样。另外「光照状态」页画的是 DLI，DLI 没有历史功能点，所以那一页是空态，
光照的历史曲线只在报表页（`reports_page.dart` 的 `SensorMetric.light`）出现。

## 变更内容

- **纪念日**（`app_backend_repository.dart`、`backend_models.dart`、`state.dart`）
  - `getAnniversaries` / `addAnniversary` / `editAnniversary` 的设备参数从 `int userProductId` 改为
    `String deviceId`；新增、编辑 body 发 `deviceId`，不再发 `userProductId`。
  - 列表：swagger 的入参里没有设备过滤，`deviceId` 仍作为 query 带上，并按返回行的 `deviceId` 再滤一次
    （返回行没带时按本设备处理）。
  - `BackendAnniversary.userProductId` 改为 `deviceId`。
  - `FlowerpotState` 删除 `_ensureBackendDevice`（纪念日是它唯一的调用方），保存前改为
    `_requireBackendSession()` 直接拿涂鸦 deviceId 调接口。
- **raw 上报解码**
  - 新增 `lib/src/tuya/tuya_raw.dart`：`TuyaRaw.bytes` 先认十六进制（偶数长度、全是 `0-9a-fA-F`），
    再认 base64，字节列表原样返回；`TuyaRaw.encodingOf` 给联调日志用。
  - `TuyaHistoryCodec` 与 `TuyaMemorialCodec.decodeRaw` 都改走 `TuyaRaw.bytes`，删掉各自那份 base64 解码。
  - `historyDiagnostics` 的日志从 `198字符/0点` 改成 `hex 99字节/96点`，编码与字节数一眼可见。
- **需水状态曲线**：`WaterStatusMetric.chartMax`（水位 200、土壤湿度 100）传给 `WaterTrendLineChart.maxValue`。
- **测试**：`test/tuya/tuya_raw_test.dart`（新增）；`tuya_history_codec_test.dart` 补十六进制日包 /
  光照周包；`memorial_codec_test.dart` 补十六进制 154 帧与 158 日期；
  `app_backend_repository_test.dart` 的纪念日用例改为 `deviceId`，并补编辑接口的 body 断言。

## 关键决策

- **十六进制优先、base64 兜底**，不是只认十六进制：Android 已从 SDK 字节码确认，iOS 桥接没有核对过；
  测试夹具也都是 base64。一段真正的 base64 恰好全由十六进制字符组成且长度为偶数，对十几字节以上的
  包概率可以忽略。
- 列表接口照带 `deviceId`：Spring 会忽略未声明的 query；后端哪天补上过滤就直接生效，没补时靠客户端再滤。
- 没有顺手清理 `_backendDevices`：改名（`editUserProduct`）和解绑（`delUserProduct`）的后端同步都以
  `_backendDevices[id] != null` 为前提，以前只有 `_ensureBackendDevice` 往里写，现在这两处等于不再调用
  已下线的接口，行为上是「只改涂鸦」。要不要删这两段、或者后端给出替代接口，留给下一轮。

## 外部操作

- 只读：`GET https://api.yikaltd.com/v2/api-docs`；不带 token 调纪念日 6 个接口与已下线的 6 个接口，
  各发一次空 body（返回 406 / HTTP 500，未产生数据）。未使用任何真实账号或 token。
- 只读：从 `maven-other.tuya.com` 的 `maven-commercial-releases` 下载 `thingsmart-device` /
  `thingsmart-hardware` / `thingsmart-device-core` / `thingsmart-dp-parser` 7.5.1 的 aar，放在 Hub 的
  忽略目录里解包看字节码调用序列，不进本仓库。
- 只读：对照 Dart SDK `sdk/lib/convert/base64.dart`，确认未补齐 padding 的输入会抛 `FormatException`。

## 验证结果

- 本机与 nas 都没有 Flutter / Dart 工具链，**`flutter analyze`、`flutter test` 未执行**，新增 / 修改的测试
  等有工具链的环境跑。
- `python3 tools/dart_string_check.py lib test`：284 个文件，无跨行未闭合字符串。
- `python3 tools/dart_dangling_refs.py lib test`：无跨类引用私有成员。
- `python3 tools/dart_nullable_await_check.py lib`：可空返回值都判过空。
- 改动的 13 个 Dart 文件做了去注释、去字符串后的 `{} () []` 配平检查，全部平衡。
- 全仓 grep：纪念日相关调用已无 `userProductId`，`lib/` 里除 `TuyaRaw` 外不再有 base64 解码。
- **未真机验证**：纪念日保存 / 编辑、报表曲线、158/159 读回，都需要装包确认。装包后先看需水状态页的联调日志，
  应为 `hex 99字节/96点` 这种形态。

## 未完成项与风险

- 新增纪念日的返回体仍按 swagger 的 `BaseOutput«boolean»`，拿不到 id 时回列表按「标题 + 日期」找回。
  列表没有设备过滤、同一账号两台花盆同一天同标题时可能取错——已按返回行 `deviceId` 过滤，风险只在后端
  返回行不带 `deviceId` 时存在。
- `refreshProductCatalog` 还在调已下线的 `getProductList`（失败被吞，搜索页回落本地常量），本轮没动。
- 光照历史全 0 需设备方确认。
- 报表页的日期导航（上一天 / 上一周）只改标题，数据始终是设备最近一次上报的那一包，本轮没动。

## 回滚或恢复

回退本提交即可；无数据迁移、无平台配置改动。
