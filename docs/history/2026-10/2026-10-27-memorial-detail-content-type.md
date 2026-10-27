# 纪念日编辑改为详情回填，内容二选一统一校验

> 文档类型：Historical Change Record
> 日期：2026-10-27；环境：远程 SSH 服务器
> 分支与起始版本：main / 8d19cf3

## 依据与范围

用户要求：编辑纪念日先回显详情接口的内容；新增也要有同样的二选一逻辑；停用时保存也走同一个保存接口，同样按二选一校验。文字/图片只能有一个有效值，按 contentType 决定显示哪个框。

## 接口文档核对（swagger，2026-10-27）

- 列表 `getProductAnniversaryList` 与详情 `getProductAnniversaryDetail?id=anniversaryId` 返回同一个模型 `ClientProductAnniversaryDetailApiOut`：`anniversaryId / deviceId / title / anniversaryDate / contentType(0文字,1图片) / content / verify(0禁用,1启用)`。
- 新增 / 编辑共用 `ClientProductAnniversaryAddApiIn`，只有一组 `contentType + content(1-150字符)`，没有分开的文字 / 图片字段，也没有清空接口；新增只返回 boolean（id 仍按标题 + 日期回列表找）。
- 启停走 `setUserProductAnniversaryVerify`（`commonIds` + `verify`）。
- 结论：后端没有更合适的拆分字段，二选一只能由 App 保证「只提交所选类型、所选类型必须有值」，回填以详情为准。

## 改动

- `FlowerpotState.loadMemorialDetail(deviceId, id)`：接了后端时按 id 现拉详情，转成 `MemorialEntry`，并替换列表中的同一条；查不到抛 `ANNIVERSARY_NOT_FOUND`；没接后端返回 null。
- `FlowerpotState.saveMemorial`：自定义条目内容为空（含停用）直接拒绝，不写后端、不发 DP154。
- `MemorialEditPage`：
  - 编辑已有自定义条目（非新增、非固定、接了后端）进页先拉详情，加载中 / 失败显示 `memorial-edit-load-state`（失败带重试），这两种状态下不显示表单和保存按钮；成功后标题、日期、启停、类型、内容全部以详情为准。
  - 回填来源 `_source` 统一为详情（或新增 / 没接后端时的路由条目），切换类型只按它回填：同类型恢复原值，另一类型为空，丢弃未保存文字和本地选图。
  - 内容非空校验不再只在启用时做，停用同样校验。
  - 混入 `NetworkRetryAware`：网络异常弹窗「重试」只在详情没拉成功时重拉，避免冲掉正在编辑的内容。
  - 去掉保存成功后清另一类型草稿的代码（成功即关页，状态里只留所选类型）。
- 测试 `memorial_page_test.dart`：详情与列表类型不一致时按详情回填（文字 / 图片两组）、加载中无保存按钮、保存只带详情类型；详情失败显示重试且不能保存、重试后回填；新增没选图不提交、文字保存只带 `contentType=0`；新增图片先上传、只带 `contentType=1` 与上传地址；停用 + 切到空类型不提交、切回原类型保存带 `verify=0`；状态层拒绝空内容。
- 文档：`PRODUCT_RULES.md` §4.24、`AI_CONTEXT.md`。

## 验证

本机无 Flutter / Dart，测试、analyze、format、编译均未运行；未真机、未用真实账号调接口。`git diff --check` 通过。需本地执行 `flutter analyze` 与 `flutter test test/features/devices/memorial_page_test.dart`。

## 未决与风险

- 上传接口 `setFileUpload` 返回 `BaseOutput<string>`，未核实是否为完整 http(s) 地址；若是相对路径，编辑页预览会加载失败，不重选图直接保存会被当本地文件重传而失败，DP154 也会拿到不完整地址。需真实接口确认。
- 编辑页依赖详情接口可用；详情接口异常时只能重试，不会退回列表数据。

## 回滚

还原对应提交即可，不涉及后端数据或固件配置。
