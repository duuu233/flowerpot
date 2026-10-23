import 'package:flutter/widgets.dart';

import 'app_language.dart';

/// 语言作用域：由 `MaterialApp.builder` 注入到 Navigator **之上**，成为所有路由
/// （含 push 出来的业务页）的祖先。切换语言时 [language] 变化，凡是通过
/// [AppL10n.of] 取文案的页面（都因此注册了对本 InheritedWidget 的依赖）都会重建。
///
/// 业务文案使用轻量目录，不生成 .arb；Material/Cupertino 内建控件另由根应用的
/// flutter_localizations delegates 跟随同一界面语言。
class AppLocalizationsScope extends InheritedWidget {
  const AppLocalizationsScope({
    required this.language,
    required super.child,
    super.key,
  });

  final AppLanguage language;

  static AppLanguage languageOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLocalizationsScope>();
    return scope?.language ?? AppLanguage.zh;
  }

  @override
  bool updateShouldNotify(AppLocalizationsScope oldWidget) =>
      language != oldWidget.language;
}

/// 界面文案目录。`AppL10n.of(context).save` 取文案，语言一变整页重译。
///
/// **加一条文案**：在下面加一个 getter，用 [t] 写成 `{语言: 文案}` 的表。
/// **加一门语言**：见 [AppLanguage]；这里的表缺条目会按回落链取，不会报错也不会空白。
///
/// 迁移状态（2026-09-08）：本目录覆盖的是本轮改动涉及的页面——设置、自动检测植物、
/// 休眠模式、其他设置、编辑纪念日、首页顶栏——**其余页面仍是硬编码中文**，逐页迁移
/// 的做法就是把 `Text('中文')` 换成 `Text(AppL10n.of(context).key)` 并在这里补条目。
/// 设备状态文案（需水/光照/温度/湿度）另有一张按功能点组织的表：`TuyaStatusCopy`。
class AppL10n {
  const AppL10n(this.language);

  final AppLanguage language;

  /// 订阅语言作用域并返回当前语言的文案目录。
  static AppL10n of(BuildContext context) =>
      AppL10n(AppLocalizationsScope.languageOf(context));

  /// 按当前语言取文案；没有当前语言的条目就按 [AppLanguage.fallbacks] 回落。
  String t(Map<AppLanguage, String> values) {
    final own = values[language];
    if (own != null) return own;
    for (final fallback in language.fallbacks) {
      final value = values[fallback];
      if (value != null) return value;
    }
    // 表里一条都没写：返回空串而不是抛异常，界面缺一句总好过整页白屏。
    return values.values.isEmpty ? '' : values.values.first;
  }

  // ── 通用 ────────────────────────────────────────────────────────────
  String get save => t(const {AppLanguage.zh: '保存', AppLanguage.en: 'Save'});

  String get on => t(const {AppLanguage.zh: '已开启', AppLanguage.en: 'On'});

  String get off => t(const {AppLanguage.zh: '已关闭', AppLanguage.en: 'Off'});

  String get deviceNotFound =>
      t(const {AppLanguage.zh: '未找到设备', AppLanguage.en: 'Device not found'});

  String get deviceNotFoundMessage => t(const {
    AppLanguage.zh: '设备不存在或已经解绑。',
    AppLanguage.en: 'This device no longer exists or has been unbound.',
  });

  String get unnamedDevice =>
      t(const {AppLanguage.zh: '我的花盆', AppLanguage.en: 'My planter'});

  String get cancel =>
      t(const {AppLanguage.zh: '取消', AppLanguage.en: 'Cancel'});

  String get retry => t(const {AppLanguage.zh: '重试', AppLanguage.en: 'Retry'});

  // ── 网络异常弹窗（全局，2026-09-15）───────────────────────────────────
  String get networkErrorTitle =>
      t(const {AppLanguage.zh: '网络异常', AppLanguage.en: 'Network error'});

  String get networkErrorMessage => t(const {
    AppLanguage.zh: '当前网络不可用，请检查网络后重试',
    AppLanguage.en:
        'The network is unavailable. Please check your connection and try again.',
  });

  // ── 设置 ────────────────────────────────────────────────────────────
  String get settings =>
      t(const {AppLanguage.zh: '设置', AppLanguage.en: 'Settings'});

  String get plantDetection => t(const {
    AppLanguage.zh: '自动检测植物',
    AppLanguage.en: 'Auto plant detection',
  });

  String get plantDetectionSwitchTitle => t(const {
    AppLanguage.zh: '启用自动检测',
    AppLanguage.en: 'Enable auto detection',
  });

  String get plantDetectionDescription => t(const {
    AppLanguage.zh:
        '开启后，东方金穗发现盆里的植物和当前记录不一致时会主动提醒，\n'
        '由你确认换成新植物还是保持原样。',
    AppLanguage.en:
        'When on, 东方金穗 asks you to confirm whenever the plant it '
        'detects differs from the one on record.',
  });

  // ── 休眠模式 ─────────────────────────────────────────────────────────
  String get standby =>
      t(const {AppLanguage.zh: '休眠模式', AppLanguage.en: 'Standby'});

  String get standbyEnable =>
      t(const {AppLanguage.zh: '开启', AppLanguage.en: 'Enable'});

  String get standbyDescription => t(const {
    AppLanguage.zh: '无操作达到延迟时间后进入休眠',
    AppLanguage.en: 'Sleep after the delay below with no interaction',
  });

  String get standbyDelay =>
      t(const {AppLanguage.zh: '延迟时间', AppLanguage.en: 'Delay'});

  String get hourUnit => t(const {AppLanguage.zh: '时', AppLanguage.en: 'h'});

  String get minuteUnit =>
      t(const {AppLanguage.zh: '分', AppLanguage.en: 'min'});

  /// 休眠延迟的合法范围提示，[min]/[max] 以分钟计。
  String standbyDelayRange(int min, int max) => t({
    AppLanguage.zh: '延迟时间需要在 $min~$max 分钟之间',
    AppLanguage.en: 'The delay must be between $min and $max minutes',
  });

  // ── 纪念日 ───────────────────────────────────────────────────────────
  String get memorialPickDate =>
      t(const {AppLanguage.zh: '请选择日期', AppLanguage.en: 'Please pick a date'});
}
