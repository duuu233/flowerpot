import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import 'widgets/mower_card.dart';
import 'widgets/mower_form.dart';

/// 语言切换（`割草机-语言切换.png`）→ **DP109 language**（enum 18 值）。
///
/// 口径（2026-09-18 用户）：
/// 1. **DP109 没内容**（设备没报过）→ 按**手机默认语言**显示默认语种；
/// 2. 正常情况按 DP109 显示选中语种；
/// 3. 点保存才下发 DP109。
///
/// ⚠️ **这 18 个枚举里没有中文**（english/german/spanish/…/lithuanian，见 [MowerLanguage]），
/// 而稿子上画的是「简体中文 / English / 繁體中文」。**列表按 DP 的 18 个来**——
/// 画三个设备根本不认的选项，用户选了也下发不出去。简中/繁中手机会落到 English，
/// 这不是 bug，是设备面板没有中文。🔶 要中文得先让设备端在 DP109 里加枚举。
class MowerLanguagePage extends StatefulWidget {
  const MowerLanguagePage({super.key});

  @override
  State<MowerLanguagePage> createState() => _MowerLanguagePageState();
}

class _MowerLanguagePageState extends State<MowerLanguagePage> {
  MowerDevice get _device => MowerDevice.instance;

  late MowerLanguage _selected = _initialLanguage();
  late final bool _fromPhone = _device.language == null;

  /// DP109 有值就用它；没有就按手机语言挑一个。
  MowerLanguage _initialLanguage() {
    final reported = _device.language;
    if (reported != null) return reported;
    return MowerLanguage.forLocale(_phoneLanguageCode);
  }

  String get _phoneLanguageCode =>
      PlatformDispatcher.instance.locale.languageCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FlowerpotScope.of(context)
        ..logPageEntry('割草机-语言切换')
        ..logMowerInteraction(
          _fromPhone
              ? '读取 ← 割草机-语言切换 DP${MowerDp.language} language 无内容，'
                    '按手机语言 $_phoneLanguageCode 取默认值 ${_selected.code}'
              : '读取 ← 割草机-语言切换 DP${MowerDp.language} language=${_selected.code}',
        );
    });
  }

  void _save() {
    final state = FlowerpotScope.of(context);
    _device.setLanguage(state, _selected);
    showAppMessage(context, '已下发 DP${MowerDp.language} = ${_selected.code}');
  }

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
                    '选择机器面板显示语言',
                    style: TextStyle(color: Color(0xFF73787A), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  MowerCard(
                    child: Column(
                      children: <Widget>[
                        for (var i = 0; i < MowerLanguage.values.length; i++) ...<Widget>[
                          _LanguageRow(
                            language: MowerLanguage.values[i],
                            selected: MowerLanguage.values[i] == _selected,
                            onTap: () => setState(
                              () => _selected = MowerLanguage.values[i],
                            ),
                          ),
                          if (i != MowerLanguage.values.length - 1)
                            const MowerRowDivider(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _fromPhone
                        ? '当前语言：${_selected.label}（DP${MowerDp.language} 无内容，按手机语言 $_phoneLanguageCode 取的默认值）'
                        : '当前语言：${_selected.label}',
                    key: const Key('mower-language-current'),
                    style: const TextStyle(
                      color: MowerColors.brand,
                      fontSize: 12,
                      height: 1.5,
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
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final MowerLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('mower-language-${language.code}'),
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      language.label,
                      style: const TextStyle(
                        color: MowerColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      // 联调要对枚举序，干脆把「序号 + 标识符」写在名字下面
                      '${language.value} · ${language.code}',
                      style: const TextStyle(
                        color: MowerColors.inkTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
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
