import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../tuya/tuya_memorial_codec.dart';

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
    text: _entry.type == MemorialContentType.text ? _entry.content : '',
  );

  /// Local path of a freshly picked image, before it is uploaded. The DP wants
  /// a URL, so this is only what the page previews.
  String? _pickedImagePath;
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
    setState(() => _pickedImagePath = file.path);
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
    setState(() => _saving = true);
    final result = await FlowerpotScope.of(context).saveMemorial(
      widget.arguments.deviceId,
      _entry.copyWith(title: title, content: content),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
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
    return _pickedImagePath ?? _entry.content;
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
            padding: const EdgeInsets.only(bottom: 96),
            child: ResponsiveContent(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                28,
                AppSpacing.pageMargin,
                24,
              ),
              child: AppSurfaceCard(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _EnableRow(
                      enabled: _entry.enabled,
                      onChanged: (value) =>
                          setState(() => _entry = _entry.copyWith(enabled: value)),
                    ),
                    const Divider(height: 32),
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
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                          ),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            counterText: '',
                            hintText: '请输入纪念日标题',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 26),
                    const _FieldLabel('日期'),
                    const SizedBox(height: 10),
                    _DateField(
                      label: _entry.dateLabel,
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 26),
                    const _FieldLabel('内容'),
                    const SizedBox(height: 10),
                    if (_fixed)
                      _FixedContentChip(label: '${_entry.title}动画')
                    else ...<Widget>[
                      _ContentTypeTabs(
                        type: _entry.type,
                        onChanged: (type) =>
                            setState(() => _entry = _entry.copyWith(type: type)),
                      ),
                      const SizedBox(height: 16),
                      if (_entry.type == MemorialContentType.text)
                        _TextContentField(controller: _textController)
                      else
                        _ImageContentSlot(
                          localPath: _pickedImagePath,
                          url: _entry.content,
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

class _FilledField extends StatelessWidget {
  const _FilledField({required this.child, this.height = 56});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: _fieldRadius,
      ),
      child: SizedBox(
        height: height,
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
      color: AppColors.canvas,
      borderRadius: _fieldRadius,
      child: InkWell(
        key: const Key('memorial-date-field'),
        borderRadius: _fieldRadius,
        onTap: onTap,
        child: SizedBox(
          height: 56,
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.full,
          border: Border.all(color: AppColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.brandPrimary,
              fontSize: 17,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentTypeTabs extends StatelessWidget {
  const _ContentTypeTabs({required this.type, required this.onChanged});

  final MemorialContentType type;
  final ValueChanged<MemorialContentType> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _Tab(
                tabKey: const Key('memorial-type-text'),
                label: '文字',
                selected: type == MemorialContentType.text,
                onTap: () => onChanged(MemorialContentType.text),
              ),
            ),
            Expanded(
              child: _Tab(
                tabKey: const Key('memorial-type-image'),
                label: '图片',
                selected: type == MemorialContentType.image,
                onTap: () => onChanged(MemorialContentType.image),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tabKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key tabKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.surface : Colors.transparent,
      borderRadius: AppRadius.card,
      child: InkWell(
        key: tabKey,
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppColors.brandPrimary
                    : AppColors.textSecondary,
                fontSize: 17,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
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
        color: AppColors.canvas,
        borderRadius: _fieldRadius,
      ),
      child: Padding(
        // 左右和标题、日期两个输入框对齐（16），上下留出与之相称的呼吸；原来是
        // 14/10 的不对称边距，配上 16 的大圆角，看着比上面两个框圆一圈也挤一圈。
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 104,
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
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  counterText: '',
                  hintText: '请输入纪念日文字内容...',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$used / ${TuyaMemorialCodec.maxTextCharacters}',
                key: const Key('memorial-text-counter'),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
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
      child: SizedBox.square(
        dimension: 132,
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
