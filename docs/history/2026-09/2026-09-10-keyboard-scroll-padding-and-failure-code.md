# 2026-09-10（晚）键盘避让补上 scrollPadding；失败码永远显示；失败页收紧间距

## 背景（用户报告）

1. 「连接 Wi-Fi」页：输入框获焦时，手机虚拟键盘仍然挡住当前输入框，希望页面按焦点
   动态往上移一点。
2. 「连接设备」（配网失败）页：失败时底部的「返回搜索设备」按钮**下半部被挡住**，
   希望缩小上面图片的间距。
3. 失败提示是「设备未能成功连接到当前WIFI网络，out of time」——**没看到任何状态码**。

环境：home / `/pgdata/pg/dh/flowerpot`，分支 `main`，起始提交 `649d22d`。

## 诊断

### 1. 键盘避让：框架默认只做对了一半

之前（`60dd74b`）把「关掉 `resizeToAvoidBottomInset` + 底部手动加 `viewInsets` padding」
那套错误写法撤掉、退回框架默认，方向是对的：`Scaffold` 默认 `resizeToAvoidBottomInset:
true` ⇒ body 按键盘缩矮 ⇒ 滚动视口跟着变矮 ⇒ `EditableText` 自动把光标滚进视口。
`AppPageScaffold` 也确实把这个参数原样透传给 `Scaffold`（不传即 null ⇒ 默认 true）。

**但漏了一件事：这一页底部浮着一颗按钮。**

`EditableText` 的自动滚动用的是 `TextField.scrollPadding`，默认 `EdgeInsets.all(20)`
——只保证光标离**视口底部** 20px 就算「可见」。而视口底部就是键盘顶部，那一带正好被
`Stack` 里 `Positioned(bottom: 8)` 的「开始配网」按钮（高 50）占着。于是自动滚动确实
发生了，输入框也确实被滚上来了，只是停在了按钮后面——用户看到的就是「还是被挡住」。

### 2. 失败页：内容一长就把底部按钮挤出首屏

`ConstrainedBox(minHeight: constraints.maxHeight)` + `Expanded` 把两颗按钮沉到底部，
内容超过一屏时改为滚动。原来的排布是 `70 + 插图 235 + 24 + 标题 + 12 + 副标题 + 20 +
小提示卡 + 24 + 按钮 50 + 12 + 按钮 50 + 24`。副标题本来按一两行排，而失败原因带上
提示语和失败码后是三四行，整体就超出一屏，最后那颗「返回搜索设备」只露上半截。

### 3. 失败码：认不出来时被整个丢掉

```dart
final hint = hintFor(code);
if (hint != null) return '$generic\n$hint（$code）';   // 认得 ⇒ 带 code
final detail = message?.trim() ?? '';
if (detail.isEmpty) return generic;
return '$generic\n$detail';                            // 认不得 ⇒ code 没了
```

**认不得恰恰是最需要这个码的情形**，代码却偏偏在这一支把它丢了。测试看到的
「……，out of time」就是这一支：`hintFor` 不认识那个码，于是只剩涂鸦的英文原文。

`out of time` 是涂鸦 activator 的超时原文。它在新流程里的含义很具体：**没有收到设备的
任何结构化回复**——收到了就会是 207xxx。也就是整条配网通道根本没建起来，不是密码错、
也不是连不上路由器。

## 改动

### `lib/src/features/devices/presentation/pairing_page.dart`

- 新增顶层常量 `_startButtonInset = 92`，替掉原来散在滚动区 padding 里的字面量 92。
  它现在有两个用途，必须是同一个数：滚动区底部让位 + 输入框 `scrollPadding` 的 bottom。
- `_CredentialInput` 的 `TextField` 加
  `scrollPadding: EdgeInsets.fromLTRB(20, 20, 20, _startButtonInset + 12)`。
  获焦时页面就会多往上滚这一段，输入框落在浮动按钮上方。
- 相关注释重写：说明键盘避让是「Scaffold 的 resize」+「输入框的 scrollPadding」两件事
  配合，并保留那条「不要再写关掉 resize 那一套」的警告。

### `lib/src/features/devices/presentation/memorial_edit_page.dart`

同一个结构（滚动区 + `Positioned(bottom: 12)` 的保存按钮），同样加
`scrollPadding: EdgeInsets.fromLTRB(20, 20, 20, 96)`。

**`plant_picker_page.dart` 不改**：它的搜索框在 `CustomScrollView` 的顶部，键盘从下面
上来挡不到它。

### `lib/src/features/devices/presentation/pairing_failure_page.dart`

- `_subtitle` 重写：`tag = code?.trim()`，`suffix = '（$tag）'`，**认得与认不得两支都
  带上 suffix**；message 也为空时退化成「失败码 xxx」，绝不再出现「一个码都看不到」。
- 新增 `_hintForMessage`：码认不出来时看涂鸦那句**没翻译的英文原文**
  （`out of time` / `timeout`），换成一句能照着做的话。只认英文——我们自己的中文文案
  （「配网超时」之类）本来就读得懂，换掉反而丢信息。
- 间距收紧：顶部 `70/28` → `36/16`；插图 235 → `200/160`（`_FailureRadar` 改为接收
  `size`）；插图下方 `24/12` → `16/10`；小提示卡上方 20 → `18/14`；按钮上方 24 →
  `20/14`。合计省下约 90px（矮屏更多），两颗按钮完整落在首屏。

### `test/features/devices/pairing_failure_page_test.dart`

新增一条：`code: 'pair_failed'` + `message: 'out of time'` ⇒ 副标题同时含
`（pair_failed）` 与「等待设备回应超时」。这正是测试报回来的那一条。

## 验证

**未验证。** 本机没有 Flutter/Dart 工具链。静态自检：

- 三个改动文件 + 测试文件括号配平通过。
- 逐条核对了现有断言不会被打破：
  - `pairing_failure_page_test.dart` 第一条用 `code: 'pair_failed'` /
    `message: '配网超时'` 断言 `contains('配网超时')`——`_hintForMessage` **只认英文**，
    所以中文原文照常透出，该断言仍成立（这也是把 `'超时'` 从匹配里去掉的原因）。
  - 第二条断言 `contains('（hotspot_join_cancelled）')` 与
    `isNot(contains('令牌 812ms'))`，走的是「认得」那一支，行为未变。
  - `find.text('设备未能成功连接到当前Wi-Fi网络')`：那是 `_FailureTipCard` 之外的独立
    文本，`_subtitle` 里的 generic 仍是同一句开头，未改。

## 遗留

- **配网失败本身没有解决**，这次只是让原因看得见。下次失败请把括号里的码带回来：
  - `207xxx` ⇒ 通道建起来了，是设备侧的具体原因（密码、路由器、DHCP、连云）；
  - 仍是 `out of time` 之类的非结构化码 ⇒ **通道没建起来**，说明 `startActivator`
    没能连上设备热点。那就得把连热点这一步显式加回配网流程里
    （在用户输完密码、点「开始配网」之后调一次 `apQueryDeviceWifi` 取它连热点的副作用，
    丢掉返回的 Wi-Fi 列表），而不是像之前那样放在搜索页——那时手机还在路由器上。
- 这次刻意**没有**同时改配网流程：先让失败码可见，再按码决定，免得两处一起动把信号搅浑。
