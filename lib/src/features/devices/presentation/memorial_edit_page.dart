import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/media/upload_image.dart';
import '../../../shared/widgets/blocking_progress.dart';
import '../../../tuya/tuya_memorial_codec.dart';
import 'device_online_guard.dart';

/// Route arguments for [MemorialEditPage].
class MemorialEditArguments {
  const MemorialEditArguments({
    required this.deviceId,
    required this.entry,
    this.creating = false,
  });

  final String deviceId;
  final MemorialEntry entry;

  /// A brand-new entry: the id is already allocated but nothing has been sent
  /// to the device, so leaving without saving must not create anything.
  final bool creating;
}

/// 编辑纪念日（`编辑纪念日-固定.png` / `-自定义-文字.png` / `-自定义-图片.png`）。
///
/// 固定的两条（生日、结婚纪念日）标题和内容都是设备内置的：DP 158/159 只带一个
/// 日期，所以那两页的标题是纯文本、内容是一枚说明用的胶囊，都不可编辑。自定义
/// 条目走 DP 154，标题、日期、文字或图片 URL 都由用户填。
class MemorialEditPage extends StatefulWidget {
  const MemorialEditPage({required this.arguments, super.key});

  final MemorialEditArguments arguments;

  @override
  State<MemorialEditPage> createState() => _MemorialEditPageState();
}

class _MemorialEditPageState extends State<MemorialEditPage> {
  late MemorialEntry _entry = widget.arguments.entry;
  late final TextEditingController _titleController = TextEditingController(
    text: _entry.title,
  );
  late final TextEditingController _textController = TextEditingController(
    text: widget.arguments.entry.type == MemorialContentType.text
        ? widget.arguments.entry.content
        : '',
  );

  /// Local path of a freshly picked image, before it is uploaded. The DP wants
  /// a URL, so this is only what the page previews.
  String? _pickedImagePath;

  // 两种内容各自保留草稿，切换不清空，也不把文字当成图片路径。
  late String _imageContent =
      widget.arguments.entry.type == MemorialContentType.image
      ? widget.arguments.entry.content
      : '';
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  bool get _fixed => _entry.isFixed;

  Future<void> _pickDate() async {
    final current = _entry.date ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2999, 12, 31),
      helpText: '选择纪念日日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _entry = _entry.copyWith(date: picked));
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;
    // 纪念日图片和定制动画一样进花盆屏幕：选完就压到 320 × 240 的框以内、
    // Baseline 4:2:0、500 KB 以内，见 [UploadImage]。压在这里而不是保存时，
    // 预览看到的就是真正会传上去的那张。
    final path = await withBlockingProgress(
      context,
      () => UploadImage.prepare(file.path),
    );
    if (!mounted) return;
    // null = 没做出一张设备能显示的图（也可能是页面已经被弹走）。不退回原图：
    // 超框或者 Progressive 的图传上去，花盆下载完是一片空白，手机上却看不出问题。
    if (path == null) {
      showAppMessage(context, '图片处理失败，换一张图片再试', tone: AppMessageTone.error);
      return;
    }
    setState(() => _pickedImagePath = path);
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _fixed ? _entry.title : _titleController.text.trim();
    if (!_fixed && title.isEmpty) {
      showAppMessage(context, '请输入纪念日标题', tone: AppMessageTone.error);
      return;
    }
    // 日期是纪念日的主键信息，没选就存下去，设备侧只会拿到一个空日期。
    if (_entry.date == null) {
      showAppMessage(
        context,
        AppL10n.of(context).memorialPickDate,
        tone: AppMessageTone.error,
      );
      return;
    }
    final content = _content();
    if (_entry.enabled && !_fixed && content.isEmpty) {
      showAppMessage(
        context,
        _entry.type == MemorialContentType.text ? '请输入纪念日文字内容' : '请先上传图片',
        tone: AppMessageTone.error,
      );
      return;
    }
    if (_entry.type == MemorialContentType.text &&
        content.runes.length > TuyaMemorialCodec.maxTextCharacters) {
      showAppMessage(
        context,
        '文字内容最多 ${TuyaMemorialCodec.maxTextCharacters} 个字',
        tone: AppMessageTone.error,
      );
      return;
    }
    // DP 154 的文字上限是「15 个汉字(45 字节)」，**字数和字节都要挡**：15 个汉字
    // 正好 45 字节，但 15 个 emoji 是 60 字节，只数字符会让帧超长、固件截断。
    if (_entry.type == MemorialContentType.text &&
        utf8.encode(content).length > TuyaMemorialCodec.maxTextBytes) {
      showAppMessage(
        context,
        '文字内容最多 ${TuyaMemorialCodec.maxTextBytes} 字节，'
        '表情符号占的字节多，请少用几个',
        tone: AppMessageTone.error,
      );
      return;
    }
    setState(() => _saving = true);
    // contentType + content 共用一个保存请求；只提交所选草稿，覆盖旧类型的值。
    final savedEntry = _entry.copyWith(title: title, content: content);
    final result = await FlowerpotScope.of(
      context,
    ).saveMemorial(widget.arguments.deviceId, savedEntry);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.success) {
        _entry = savedEntry;
        // 仅保存成功后丢弃另一类型草稿；失败仍允许切回继续编辑。
        if (savedEntry.type == MemorialContentType.text) {
          _imageContent = '';
          _pickedImagePath = null;
        } else {
          _textController.clear();
        }
      }
    });
    showDeviceActionResult(context, result, announceSuccess: true);
    if (result.success) Navigator.pop(context);
  }

  /// 帧里放什么。图片条目放的是 URL；刚从相册挑的还是本地路径，交给
  /// [FlowerpotState.saveMemorial]，它会先上传换成 URL 再写帧和后端。没重新挑
  /// 图就沿用上次存下来的地址。
  String _content() {
    if (_fixed) return '';
    if (_entry.type == MemorialContentType.text) {
      return _textController.text.trim();
    }
    return _pickedImagePath ?? _imageContent;
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '编辑纪念日', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: Stack(
        children: <Widget>[
          SingleChildScrollView(
            key: const Key('memorial-edit-scroll-view'),
            // 96 = 底部那颗浮着的保存按钮的占位（bottom: 12 + 高 50 + 余量）。
            // 输入框的 scrollPadding 用的是同一个数，见下面那行注释。
            padding: const EdgeInsets.only(bottom: 96),
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                28,
                AppSpacing.pageMargin,
                24,
              ),
              child: AppSurfaceCard(
                // 左右 24 是设计稿量的（卡片 335 宽、字段 286 宽，两边各 24.5）。
                // 稿子 513:2155 卡片内边距约 22/15/22/16（原 24/20/24/24，整卡比稿子高约 50）。
                padding: const EdgeInsets.fromLTRB(22, 15, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _EnableRow(
                      enabled: _entry.enabled,
                      onChanged: (value) => setState(
                        () => _entry = _entry.copyWith(enabled: value),
                      ),
                    ),
                    const Divider(height: 40),
                    const _FieldLabel('标题'),
                    const SizedBox(height: 10),
                    if (_fixed)
                      Text(
                        _entry.title,
                        key: const Key('memorial-fixed-title'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      _FilledField(
                        child: TextField(
                          key: const Key('memorial-title-field'),
                          controller: _titleController,
                          maxLength: 20,
                          // 和「连接 Wi-Fi」页同一个坑：Scaffold 默认会按键盘把
                          // body 缩矮、框架也会把光标滚进视口，但默认只留 20px，
                          // 而那 20px 正好被浮在底部的保存按钮（bottom: 12 + 高 50）
                          // 占着。把按钮的占位算进来，获焦时页面就多往上滚一点。
                          scrollPadding: const EdgeInsets.fromLTRB(
                            20,
                            20,
                            20,
                            96,
                          ),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                          ),
                          decoration: _bareFieldDecoration('请输入纪念日标题'),
                        ),
                      ),
                    const SizedBox(height: 22),
                    const _FieldLabel('日期'),
                    const SizedBox(height: 10),
                    _DateField(label: _entry.dateLabel, onTap: _pickDate),
                    const SizedBox(height: 22),
                    _FieldLabel(_fixed ? '内容' : '内容 （类型二选一）'),
                    const SizedBox(height: 10),
                    if (_fixed)
                      _FixedContentChip(label: '${_entry.title}动画')
                    else ...<Widget>[
                      _ContentTypeSelector(
                        type: _entry.type,
                        onChanged: (type) => setState(
                          () => _entry = _entry.copyWith(type: type),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_entry.type == MemorialContentType.text)
                        _TextContentField(controller: _textController)
                      else
                        _ImageContentSlot(
                          localPath: _pickedImagePath,
                          url: _imageContent,
                          onTap: _pickImage,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.pageMargin,
            right: AppSpacing.pageMargin,
            bottom: 12,
            child: AppPrimaryButton(
              key: const Key('memorial-save'),
              label: '保存',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnableRow extends StatelessWidget {
  const _EnableRow({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '启用纪念日',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                enabled ? '已开启' : '已停用',
                style: const TextStyle(
                  color: AppColors.brandPrimary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        Switch(
          key: const Key('memorial-enable-switch'),
          value: enabled,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
    );
  }
}

/// 三个输入框（标题 / 日期 / 文字内容）共用的圆角。
///
/// 设计稿上这三个框是同一个形状，之前统一用 `AppRadius.card`（16），在这种矮框上
/// 显得过圆；12 更贴设计稿，也不会把 46~56 高的框做成胶囊。
const BorderRadius _fieldRadius = BorderRadius.all(Radius.circular(12));

/// 标题框与日期框的高度，量自
/// `docs/UI/v2/智能花盆ysplanter/编辑纪念日-自定义-文字.png`。
const double _fieldHeight = 48;

/// 文字内容框的整体高度，同上量得约 109。
///
/// 里面是「输入区 + 右下角计数」，所以不能只按输入行数估——原来写成
/// 上下 16/12 的内边距加 104 的输入区，整块有 150+，比稿子高了三分之一，
/// 这就是产品说的「内容输入部分边距不对」。
const double _contentFieldHeight = 109;

/// 文字输入区本身的高度：总高减去上下内边距、计数行和它上面那点间距。
/// 12 + 输入区 + 4 + 16(计数行 13×1.2 取整) + 10 = 109。
const double _contentInputHeight = _contentFieldHeight - 12 - 4 - 16 - 10;

/// 灰底框里的输入框：只画文字和光标，不画自己的底色和边框。
///
/// ⚠️ 只写 `border: InputBorder.none` 不够。全局 `inputDecorationTheme`
/// （`app_theme.dart`）是 `filled: true` + 白色 `fillColor` + 胶囊形
/// `enabledBorder` / `focusedBorder`（圆角 999），`InputDecoration` 里没写的这几项
/// 会从主题补回来。结果是灰框里又套了一个紧贴文字的白色胶囊：圆角过大、左右离灰框
/// 16px、上下完全没有留白——2026-09-13 产品反馈的就是这个，标题框和文字内容框都中招。
/// 所以这里把底色和三种状态的边框都显式关掉，灰底和内边距只由外面那层框负责。
InputDecoration _bareFieldDecoration(String hintText) => InputDecoration(
  isCollapsed: true,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  counterText: '',
  hintText: hintText,
  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 17),
);

class _FilledField extends StatelessWidget {
  const _FilledField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: _fieldRadius,
      ),
      child: SizedBox(
        // 48 是从设计稿量的（标题框与日期框同高）。原来写的 56 比稿子高一截，
        // 三个框叠起来整张卡片就被撑长了。
        height: _fieldHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.fieldFill,
      borderRadius: _fieldRadius,
      child: InkWell(
        key: const Key('memorial-date-field'),
        borderRadius: _fieldRadius,
        onTap: onTap,
        child: SizedBox(
          height: _fieldHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                    ),
                  ),
                ),
                const Icon(
                  Icons.calendar_month_outlined,
                  color: AppColors.brandPrimary,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The fixed pair's content is firmware artwork, so the frame shows a label
/// rather than an editor.
class _FixedContentChip extends StatelessWidget {
  const _FixedContentChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      // 稿子 513:2025：和分段控件同一套外观，只放一格——灰底 44 高、圆角 12，
      // 里面白色选中块 38 高、圆角 10。
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.fieldFill,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 142, minHeight: 38),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.brandPrimary,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentTypeSelector extends StatelessWidget {
  const _ContentTypeSelector({required this.type, required this.onChanged});

  final MemorialContentType type;
  final ValueChanged<MemorialContentType> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<MemorialContentType>(
      groupValue: type,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      child: Row(
        children: <Widget>[
          for (final item in MemorialContentType.values)
            Expanded(
              child: RadioListTile<MemorialContentType>(
                key: Key(
                  item == MemorialContentType.text
                      ? 'memorial-type-text'
                      : 'memorial-type-image',
                ),
                value: item,
                activeColor: AppColors.brandPrimary,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: Text(
                  item == MemorialContentType.text ? '文字' : '图片',
                  style: TextStyle(
                    color: type == item
                        ? AppColors.brandPrimary
                        : AppColors.textSecondary,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TextContentField extends StatefulWidget {
  const _TextContentField({required this.controller});

  final TextEditingController controller;

  @override
  State<_TextContentField> createState() => _TextContentFieldState();
}

class _TextContentFieldState extends State<_TextContentField> {
  @override
  Widget build(BuildContext context) {
    final used = widget.controller.text.runes.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: _fieldRadius,
      ),
      child: Padding(
        // 左右和标题、日期两个框对齐（16）；上下按设计稿的总高 109 倒推：
        // 12(上) + 输入区 + 4 + 计数行 + 10(下)。
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: _contentInputHeight,
              child: TextField(
                key: const Key('memorial-text-field'),
                controller: widget.controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                // 设备侧上限是 15 个汉字（45 字节），超了固件会截断，所以在
                // 输入这一步就挡住，别让用户看到一条被砍一半的祝福语。
                maxLength: TuyaMemorialCodec.maxTextCharacters,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  height: 1.5,
                ),
                decoration: _bareFieldDecoration('请输入纪念日文字内容...'),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$used / ${TuyaMemorialCodec.maxTextCharacters}',
                key: const Key('memorial-text-counter'),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageContentSlot extends StatelessWidget {
  const _ImageContentSlot({
    required this.localPath,
    required this.url,
    required this.onTap,
  });

  final String? localPath;
  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = localPath;
    return Align(
      alignment: Alignment.centerLeft,
      // 稿子上传框 143×147（原 132 见方）。
      child: SizedBox(
        width: 143,
        height: 147,
        child: AppDashedBorder(
          child: Material(
            color: AppColors.brandSurface.withValues(alpha: .34),
            borderRadius: AppRadius.card,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('memorial-image-slot'),
              onTap: onTap,
              child: preview != null
                  ? Image.file(File(preview), fit: BoxFit.cover)
                  : url.isNotEmpty
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _UploadPrompt(),
                    )
                  : const _UploadPrompt(),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadPrompt extends StatelessWidget {
  const _UploadPrompt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.brandPrimary.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: const SizedBox.square(
            dimension: 42,
            child: Icon(Icons.add, color: AppColors.brandPrimary, size: 22),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '上传图片',
          style: TextStyle(color: AppColors.brandPrimary, fontSize: 15),
        ),
      ],
    );
  }
}
