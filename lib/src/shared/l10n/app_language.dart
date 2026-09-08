import 'package:flutter/widgets.dart';

/// 界面语言。
///
/// 现在只落地简体中文和英文，产品规划要到 18 种，所以这里按「加一个枚举值 + 在
/// 文案表里补一条」的形状留扩展位：
///
/// 1. 在下面加一个枚举值，写清 [code]（持久化、后端 `language` 参数、[locale] 都用它）
///    和 [label]（语言自己的名字——语言列表不该用当前界面语言去写别的语言的名字）；
/// 2. 在 `AppL10n` 的文案表里给这门语言补条目，缺的条目按 [fallbacks] 回落，
///    所以可以先翻一半再翻另一半，不会出现空白界面；
/// 3. 如果新语言要带脚本（例如 `zh-Hant`），[locale] 已经按 `-` 拆好了。
///
/// 注意：Material / Cupertino 内建组件的文案（长按菜单、返回键无障碍标签等）跟
/// 语言走还需要 `flutter_localizations` 依赖，本项目尚未引入，那部分目前恒为英文。
enum AppLanguage {
  zh('zh', '简体中文'),
  en('en', 'English');

  const AppLanguage(this.code, this.label);

  /// 持久化与接口用的语言标识，例如 `zh`、`en`、`zh-Hant`。
  final String code;

  /// 语言自己的名字，语言设置页直接显示这一列。
  final String label;

  /// `MaterialApp.locale` 用的 Locale。
  Locale get locale {
    final parts = code.split('-');
    if (parts.length == 1) return Locale(parts.first);
    return Locale.fromSubtags(languageCode: parts.first, scriptCode: parts[1]);
  }

  /// 缺译文时的回落顺序（不含自身）。简体中文是文案源语言，永远兜在最后。
  List<AppLanguage> get fallbacks => switch (this) {
    AppLanguage.zh => const <AppLanguage>[AppLanguage.en],
    _ => const <AppLanguage>[AppLanguage.en, AppLanguage.zh],
  };

  /// 认不出的语言码按简体中文处理（历史上存过 `zh`/`en` 以外的值也不至于崩）。
  static AppLanguage fromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return AppLanguage.zh;
    for (final language in AppLanguage.values) {
      if (language.code.toLowerCase() == normalized) return language;
    }
    // `zh-Hans`、`en-US` 这类带地区的值按主语言归类。
    final primary = normalized.split(RegExp(r'[-_]')).first;
    for (final language in AppLanguage.values) {
      if (language.code.toLowerCase().split('-').first == primary) {
        return language;
      }
    }
    return AppLanguage.zh;
  }
}
