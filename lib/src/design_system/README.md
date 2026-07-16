# YSplanter Design System

公共 Widget 统一通过 design_system.dart 引入。

## 分类

- tokens：颜色、字体、间距、圆角、阴影、动效和断点
- theme：Material 3 主题和语义扩展
- layout：页面骨架、响应式内容区、Section 和底部操作区
- navigation：页面标题栏、返回按钮和底部导航
- buttons：主按钮、描边按钮、文本按钮和图标按钮
- forms：通用输入框、手机号、验证码、密码、搜索和勾选框
- cards：基础卡片、提示卡和养护建议卡
- settings：设置列表、设置项和开关设置项
- data_display：状态、指标、头像、步骤、日期和时间范围
- feedback：加载、空状态、错误、结果、Snackbar 和确认弹窗
- dialogs：通用选项弹窗和 Bottom Sheet
- charts：图表内容卡片容器

## 边界

- 无业务含义、可跨三个以上 Feature 使用的 Widget 放在此目录。
- 植物卡片、设备卡片和校准向导等业务 Widget 保留在所属 Feature。
- 页面不得在本目录中直接访问 Repository、API、Tuya SDK 或状态管理对象。
