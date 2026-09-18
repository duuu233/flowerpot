import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../mower_demo.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_form.dart';

/// 语言切换（`割草机-语言切换.png`）：三个选项、当前语言、保存。
///
/// 静态页：选中项只改这一页自己的状态，不动 App 的语言设置。
class MowerLanguagePage extends StatefulWidget {
  const MowerLanguagePage({super.key});

  @override
  State<MowerLanguagePage> createState() => _MowerLanguagePageState();
}

class _MowerLanguagePageState extends State<MowerLanguagePage> {
  String _selected = MowerDemoDevice.language;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '语言切换', leading: AppBackButton()),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              key: const Key('mower-language-scroll-view'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    '选择应用界面显示语言',
                    style: TextStyle(
                      color: Color(0xFF73787A),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  MowerCard(
                    child: Column(
                      children: <Widget>[
                        for (
                          var i = 0;
                          i < MowerDemoLanguages.options.length;
                          i++
                        ) ...<Widget>[
                          _LanguageRow(
                            label: MowerDemoLanguages.options[i],
                            selected:
                                MowerDemoLanguages.options[i] == _selected,
                            onTap: () => setState(
                              () => _selected = MowerDemoLanguages.options[i],
                            ),
                          ),
                          if (i != MowerDemoLanguages.options.length - 1)
                            const MowerRowDivider(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '当前语言：$_selected',
                    key: const Key('mower-language-current'),
                    style: const TextStyle(
                      color: MowerColors.brand,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: MowerSaveButton(
              buttonKey: const Key('mower-language-save'),
              onPressed: () => showAppMessage(
                context,
                '静态页面：语言不会真的切换',
                tone: AppMessageTone.info,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('mower-language-$label'),
      onTap: onTap,
      child: SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: MowerColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? MowerColors.brand : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? MowerColors.brand
                        : MowerColors.inkTertiary,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
