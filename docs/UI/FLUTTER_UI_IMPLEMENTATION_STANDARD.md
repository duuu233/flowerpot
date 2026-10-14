# Flutter UI 页面实施规范

本规范适用于本项目后续所有根据 Figma 页面或 UI 截图新增、还原和调整的 Flutter 页面。除非后续任务明确提出不同要求，否则默认按本规范执行，用户无需重复说明。

> 备注：当前项目有一个位于同目录下的兄弟 Flutter 项目，开发机路径为 `D:\Work\learn\flutter`。公共功能的业务逻辑、数据组织和交互方式可以参考该兄弟项目；UI 样式仍必须以本项目当前 Figma、Design Token 和组件规范为准。例如帮助中心可复用兄弟项目的 FAQ 展开/收起逻辑，但不得直接沿用其视觉样式。

## 一、固定实现要求

每个页面必须满足：

1. 使用项目已有 `design_system`。
2. 优先使用已有公共 Widgets。
3. 不创建功能、视觉和职责重复的组件。
4. 使用 Material 3。
5. 适配 iPhone 页面尺寸、安全区域和纵向滚动。
6. 在可获得的设计信息范围内完整还原 UI，包括布局、尺寸、颜色、字体、间距、圆角、描边、阴影和层级关系。
7. 缺少独立图片资源时使用语义色块占位，不裁切 Figma 截图、不把整张截图作为页面背景；获得正式素材后只替换图片层。

## 弹框内容与滚动

弹框长内容须受可用高度约束、可纵向滚动，并显示可操作的滚动条；操作按钮保持可见。短内容不为显示滚动条而强行撑高。优先复用 `AppDialogScrollView`/`AppDialogScrollbar`，与内嵌时间滚轮分别绑定控制器；当前覆盖及手工验收见 [DIALOG_SCROLLING.md](DIALOG_SCROLLING.md)。配网失败页面原有一屏平铺规则维持。

## 二、固定输出内容

每次新增页面必须提供以下三层结构：

### 1. Page

- 文件位置：`lib/src/features/<feature>/presentation/<page>_page.dart`
- 负责页面级状态获取、页面布局组合、刷新、导航和事件分发。
- Page 不堆积可独立维护的大段 UI。

### 2. Widget 拆分

- 文件位置：`lib/src/features/<feature>/presentation/widgets/`
- 文件命名：`<page>_<section>.dart`
- 只拆分该页面特有、具有明确视觉或业务语义的区域。
- 卡片、按钮、输入框、头像、图标容器、列表、弹层、加载状态等通用能力必须复用 `design_system`。
- 当现有公共组件能力不足时，优先为原组件增加向后兼容的可选参数，不创建同类重复组件。

### 3. Model 结构

- 文件位置：`lib/src/features/<feature>/models/<page>_model.dart`
- 页面展示数据与 Flutter Widget 解耦。
- API、设备或状态层数据通过工厂方法或 Mapper 转换成页面 Model。
- 页面存在多种 Figma 场景时，使用枚举或显式状态字段控制局部显示；不同场景复用同一个 Page 和 Widget，不复制整页。
- 无 API 数据时允许提供明确的设计占位数据，但不得影响后续真实数据接入。

## 三、Design System 复用顺序

实现页面时按以下顺序选择能力：

1. Design Token：颜色、字体、间距、圆角、阴影、动画时长和断点。
2. Design System 公共组件。
3. 已有 Shared Widget。
4. Feature 内页面专属 Widget。
5. 只有多个 Feature 确认复用后，才将页面专属 Widget 上移为公共组件。

禁止在页面内重新定义已有 Token，禁止建立仅名称不同但功能相同的 Widget。

## 四、Material 3 要求

- 使用项目统一的 `ThemeData(useMaterial3: true)`。
- 页面通过 `ColorScheme`、TextTheme 和 Design Token 获取视觉属性。
- 点击、焦点、禁用、加载、错误等交互状态遵循 Material 3。
- 页面导航、SnackBar、Dialog、BottomSheet 等优先使用现有 Design System 封装。
- ⚠️ **自己画了底框的输入框，要把主题的底色和边框显式关掉。** 全局 `inputDecorationTheme` 是 `filled: true` + 白色 `fillColor` + 胶囊 `enabledBorder`/`focusedBorder`（圆角 999）。只写 `border: InputBorder.none` 挡不住：`InputDecoration` 里没写的 `filled`、`enabledBorder`、`focusedBorder` 都会从主题补回来，灰框里就会套一个紧贴文字的白胶囊。要写全 `filled: false` 加上 `border` / `enabledBorder` / `focusedBorder` / `disabledBorder: InputBorder.none`（参考 `memorial_edit_page.dart` 的 `_bareFieldDecoration`、`account_password_form_card.dart`）。2026-09-13 纪念日编辑页踩过。
- ⚠️ **`VerticalDivider` / `Divider` 不写 `width`/`height` 时取的是主题 `dividerTheme.space`（本项目为 1），不是 Material 默认的 16**，线两边没有任何留白。需要留白时用 `margin` 或 `SizedBox` 显式给出（参考需水状态卡的指标行）。

## 五、iPhone 适配要求

- 默认以 Figma 提供的 iPhone 尺寸为设计基准；未明确时使用 `375 × 812`。
- 必须使用 `SafeArea` 或项目提供的安全区域 Scaffold。
- 内容在宽屏 iPhone 上限制最大宽度并居中，不应无限拉伸。
- 小屏 iPhone 自动收紧水平间距，必要时允许纵向滚动。
- 固定尺寸仅用于设计明确的局部视觉，不得导致文字或页面整体溢出。
- 至少验证：
  - `375 × 812` 基准视口。
  - `320 × 568` 紧凑视口。
- 页面不得出现 RenderFlex overflow、被系统安全区遮挡或无法滚动到的操作项。

## 六、UI 还原检查项

每个页面交付前逐项核对：

- 页面背景和渐变方向。
- 内容最大宽度与水平边距。页面左右边距统一取 `AppSpacing.pageMargin`（当前 18），不要在页面里写死 20；设计稿标注的是 20，实际渲染时卡片阴影会额外占宽，因此收窄了 2。改这一个常量即可整体重调。
- 模块纵向顺序和相对位置。
- 字号、字重、行高、颜色和对齐方式。
- 卡片尺寸、圆角、描边、透明度和阴影。
- 图标类型、尺寸、颜色及背景容器。
- 列表行高、内边距和点击区域。
- 左侧内容、右侧进入箭头且整行可点击的布局统一使用 `AppTrailingChevron`（16 × 16）；日期前后切换等独立方向控制不套用此规则。
- 多场景之间的显示、隐藏和间距变化。
- iPhone 顶部、底部安全区域。
- 缺失图片是否按色块占位规则处理。

## 七、导航和状态管理

- 页面跳转统一使用项目路由定义，不在 Widget 中写散落的字符串路由。
- Page 负责把事件映射为导航或状态操作，展示 Widget 通过回调保持可复用和可测试。
- 页面不得直接耦合具体网络请求实现。
- 后续 API 数据先进入 Repository/状态层，再转换为页面 Model。
- 加载、空数据、错误和正常内容优先使用已有公共状态 Widget。

## 八、质量验证

页面采用批次开发、统一验证的方式：

- 默认连续完成约 5 个页面后执行一次完整校验；如果当前阶段不足 5 页，则在阶段交付前统一校验。
- 单页开发过程中只进行必要的格式化、语法或局部编译检查，避免重复执行完整回归测试。
- 每个页面仍需同步补充对应测试用例，统一在批次校验时运行。

每个页面批次完成后必须执行：

1. 批量 Dart Format。
2. Dart Analyze，要求无错误和警告。
3. 全量 Flutter Widget Test。
4. 基准 iPhone 与紧凑 iPhone 视口测试。
5. 页面场景切换与路由回归测试。
6. 核对没有新增重复公共组件。
7. 核对没有把设计截图作为页面图片使用。

## 九、页面实施记录

每个新增页面都应在 `docs/UI/` 中建立对应的实施说明 Markdown，至少记录：

- Page 文件。
- Widget 拆分及职责。
- Model 结构和场景状态。
- Design System 复用情况。
- 图片资源与占位策略。
- 页面跳转关系。
- 尺寸适配与测试结果。
- 所属开发批次及批次校验状态。

## 十、默认交付格式

每次 UI 页面任务完成后，交付结果至少包含：

1. `page.dart` 路径。
2. Widget 拆分文件列表。
3. Model 文件及结构说明。
4. 页面实施说明 `.md` 路径。
5. 静态分析和测试结果。

本文件为后续 UI 页面开发的默认执行标准。
