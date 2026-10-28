# 纪念日文字回填按设备上限截断

> 文档类型：Historical Change Record
> 日期：2026-10-28；环境：远程 SSH 服务器
> 分支与起始版本：main / 8ede53c

## 依据与范围

反馈：图片纪念日保存后再进入，详情返回的类型是文字、内容是图片地址，文字框显示整串地址；关掉开关保存被「文字内容最多 15 个字」拦住，只能删掉地址打一个字才能保存。用户要求：回填直接截断，输入框最多 15 个字超过不让输入。详情类型为何不是图片由用户另与接口确认，本次不改类型判断。

## 改动

- `MemorialEditPage._sourceText()`：文字框的所有回填（初始、详情拉到后、切回文字类型）取回填来源的文字内容，先按字符截到 `TuyaMemorialCodec.maxTextCharacters`（15），再逐个去掉末尾字符直到 UTF-8 不超过 `maxTextBytes`（45）。`TextField.maxLength` 只挡手动输入，不管程序填入的值，所以要在回填处截。
- 图片回填、保存校验、`saveMemorial` 不变。
- 测试 `memorial_page_test.dart`：详情文字为 URL 时回填截成前 15 字，停用后保存成功、提交截断内容且 `verify=0`；15 个 emoji 回填截成 11 个（44 字节）。
- 文档：`PRODUCT_RULES.md` §4.24、`AI_CONTEXT.md`、`docs/reports/2026-10-27至10-28-花盆APP改动说明.md` 第五节。

## 验证

本机无 Flutter / Dart，测试、analyze、format、编译均未运行；未真机。`git diff --check` 通过。需本地执行 `flutter analyze` 与 `flutter test test/features/devices/memorial_page_test.dart`。

## 未决

- 图片保存（`contentType=1`）后详情返回非 1 的原因待接口确认；若为后端未更新类型，截断只解决「保存不了」，图片仍会显示成截断后的文字。

## 回滚

还原对应提交即可。
