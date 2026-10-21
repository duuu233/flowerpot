import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/config/debug_log_gate.dart';

import '../../app/flowerpot_app.dart';
import '../mower/mower_ui.dart';
import '../mower/presentation/widgets/mower_card.dart';
import 'message_category_tabs.dart';

/// 花盆和割草机共用的涂鸦云端历史消息通知列表。
///
/// 三栏都按当前设备取MSG_REPORT，由loadAllDeviceMessages分页加载。
/// 默认按推送等级分栏：通知进日志、轻微进提醒、严重及未知等级进告警。
/// 割草机开启[groupByTitle]：设备通知进日志、设备异常进告警、其它标题进提醒。
/// 分类依据只影响分栏，消息标题、内容、时间与云端来源不变。
///
/// 日期筛选默认全部日期，各栏独立按天筛选；收到推送后2秒重新拉取。
class DeviceMessagesView extends StatefulWidget {
  const DeviceMessagesView({
    required this.deviceId,
    required this.pageName,
    required this.keyPrefix,
    this.footer,
    this.logsEntry = true,
    this.groupByTitle = false,
    super.key,
  });

  /// 查哪台设备的消息（涂鸦 `msgSrcId`）。null = 还没绑到设备，什么都不取。
  final String? deviceId;

  /// 联调日志里的页面名（「割草机-消息通知」「花盆-消息通知」），分档结果也按它打，两边分得开。
  final String pageName;

  /// 控件 key 的前缀：割草机沿用原来的 `mower-messages`，花盆用 `device-messages`。
  final String keyPrefix;

  /// 列表下方可选的附加内容；割草机消息页不传入调试组件。
  final Widget? footer;

  /// 进页面时按 [pageName] 记一行「进入 ← [页面名]」。花盆的页面走 `/devices/` 路由，路由监听
  /// （`interaction_log_overlay.dart`）已经记过了，传 false 免得记两行。
  final bool logsEntry;

  /// 按显示标题匹配设备通知/设备异常，其余归提醒；默认保留推送等级分类。
  final bool groupByTitle;

  @override
  State<DeviceMessagesView> createState() => _DeviceMessagesViewState();
}

/// 三个分类（界面文案）。
const List<String> _tabs = <String>['日志', '提醒', '告警'];

/// 等级模式调试台用：一条消息按等级规则分到哪一栏，写成一句话，
/// 如「告警(严重)，依据 alarmType=3（推测编码）」「告警(严重)，没认出等级，按告警」。
/// 规则只在 `_DeviceMessagesViewState._gradeOf` 一处，这里只是转一下。
String describeMessageGrade(Map<Object?, Object?> item) {
  final at = _DeviceMessagesViewState._alarmEntry(item).at;
  final grade = _DeviceMessagesViewState._gradeOf(item, at);
  final basis = grade.basis;
  return '${_tabs[grade.level.tab]}(${grade.level.label})，'
      '${basis == null ? '没认出等级，按告警' : '依据 $basis${grade.guessed ? '（推测编码）' : ''}'}';
}

/// 平台推送规则的三个等级 → 页面三栏（2026-09-28 产品：**日志 = 通知、提醒 = 轻微、告警 = 严重**）。
enum _PushLevel {
  notice('通知'),
  minor('轻微'),
  severe('严重');

  const _PushLevel(this.label);

  final String label;

  /// 第几栏（和 [_tabs] 一一对应）。
  int get tab => index;
}

/// 数字等级 → 等级。
///
/// ⚠️ **推测，待真机确认**：涂鸦文档没写等级的编码。按 1 = 通知、2 = 轻微、3 = 严重（家庭 / 通知档消息的
/// `alarmType` 都是 0，所以 0 当「没有等级」）。真机上分别触发三个等级的推送，看联调日志里每条的
/// `warnLevel`（设备告警监听 `warn56`）与 `alarmType`，对不上就改这张表，别处不用动。
const Map<int, _PushLevel> _levelCodes = <int, _PushLevel>{
  1: _PushLevel.notice,
  2: _PushLevel.minor,
  3: _PushLevel.severe,
};

class _DeviceMessagesViewState extends State<DeviceMessagesView> {
  int _tab = 0;

  /// 每一栏各自的日期筛选，`null` = 全部日期（默认全部，以前的推送都看得到）。
  final List<DateTime?> _days = <DateTime?>[null, null, null];
  bool _loading = false;

  /// 三栏的条目（按 [_PushLevel.tab] 放），都来自消息中心告警档。
  List<List<_Entry>> _entries = const <List<_Entry>>[
    <_Entry>[],
    <_Entry>[],
    <_Entry>[],
  ];

  /// 取数失败时的一句话（原样来自接口 / 原生诊断）。三栏同一个来源，共用一个。
  String? _error;

  /// 页面开着时收到的设备告警（`warn56`，自带 `warnLevel`）：按时间和消息中心的消息对上，给那条定等级。
  final List<({String devId, DateTime at, int level})> _warns =
      <({String devId, DateTime at, int level})>[];

  StreamSubscription<Map<String, Object?>>? _pushSub;
  Timer? _pushReload;

  /// 每次 [_reload] 的序号：并发的几次查询只让最后发起的那次落到页面上。
  int _reloadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = FlowerpotScope.of(context);
      if (widget.logsEntry) state.logPageEntry(widget.pageName);
      unawaited(_reload());
      // 页面开着时收涂鸦实时推送：来一条就立刻重拉；消息中心落库可能比推送晚一点，
      // 2 秒后再补拉一次（2026-10-21 用户「不做任何延时」：不再先干等 2 秒）。
      // SDK 的监听整个进程只注册一次，重复进页面不会重复注册（见 FlowerpotState.startPushListen）；
      // 设备告警（warn56）的监听随设备 DP 监听一起挂在原生侧（MainActivity.registerWarnListener）。
      unawaited(state.startPushListen());
      _pushSub = state.pushMessages.listen((event) {
        if (!mounted) return;
        if (!widget.groupByTitle) _rememberWarn(event);
        unawaited(_reload());
        _pushReload?.cancel();
        _pushReload = Timer(const Duration(seconds: 2), () {
          if (mounted) unawaited(_reload());
        });
      });
    });
  }

  @override
  void dispose() {
    _pushReload?.cancel();
    unawaited(_pushSub?.cancel());
    super.dispose();
  }

  DateTime? get _day => _days[_tab];

  /// 记下一条设备告警（`source=warn56`）的设备、时间、等级。时间是毫秒还是秒没有文档，按大小认。
  void _rememberWarn(Map<String, Object?> event) {
    if (!mounted || '${event['source'] ?? ''}' != 'warn56') return;
    final fields = event['fields'];
    if (fields is! Map) return;
    final level = int.tryParse('${fields['warnLevel'] ?? ''}');
    final raw = int.tryParse('${fields['latestWarnTime'] ?? ''}');
    final received = int.tryParse('${event['receivedAt'] ?? ''}');
    final millis = raw == null
        ? received
        : (raw > 100000000000 ? raw : raw * 1000);
    if (level == null || millis == null) return;
    _warns.add((
      devId: '${fields['devId'] ?? ''}',
      at: DateTime.fromMillisecondsSinceEpoch(millis),
      level: level,
    ));
    FlowerpotScope.of(context).logNote(
      '${widget.pageName} 设备告警 warn56：devId=${fields['devId']} warnLevel=$level '
      '（按推测编码 = ${_levelCodes[level]?.label ?? '未知'}）latestWarnTime=$raw',
    );
  }

  Future<void> _reload() async {
    final state = FlowerpotScope.of(context);
    final deviceId = widget.deviceId;
    if (deviceId == null) return;
    final generation = ++_reloadGeneration;
    setState(() => _loading = true);
    final messages = await state.loadAllDeviceMessages(deviceId: deviceId);
    if (!mounted || generation != _reloadGeneration) return;
    final buckets = <List<_Entry>>[<_Entry>[], <_Entry>[], <_Entry>[]];
    final notes = <String>[];
    var unknown = 0;
    var guessed = 0;
    for (final item
        in (messages['items'] as List<Object?>?) ?? const <Object?>[]) {
      if (item is! Map) continue;
      final entry = _alarmEntry(item);
      final grade = widget.groupByTitle
          ? _gradeByTitle(entry.title)
          : _gradeOf(item, entry.at, _warns);
      buckets[grade.level.tab].add(entry);
      if (grade.basis == null) {
        unknown++;
      } else if (grade.guessed) {
        guessed++;
      }
      if (notes.length < 5) {
        notes.add(
          widget.groupByTitle
              ? '${entry.title} → ${_tabs[grade.level.tab]}（按标题分类）'
              : _gradeFields(item, grade),
        );
      }
    }
    for (final list in buckets) {
      list.sort((a, b) => b.at.compareTo(a.at));
    }
    if (messages['ok'] == true) {
      final rule = widget.groupByTitle
          ? '（按标题分类，其余标题归提醒）'
          : '（按推测编码 $guessed 条，认不出等级 $unknown 条按告警）';
      state.logNote(
        '${widget.pageName} 分档：共 ${buckets.fold<int>(0, (sum, list) => sum + list.length)} 条 → '
        '日志 ${buckets[0].length}、提醒 ${buckets[1].length}、告警 ${buckets[2].length}$rule',
      );
      for (final note in notes) {
        state.logNote('${widget.pageName} 等级字段：$note');
      }
    }
    setState(() {
      _loading = false;
      _entries = buckets;
      _error = messages['ok'] == true ? null : _reason(messages);
    });
  }

  static String _reason(Map<String, Object?> data) => !DebugLogGate.enabled
      ? '消息加载失败，请稍后重试'
      : '${data['message'] ?? (data['diagnostic'] as List<Object?>?)?.join('；') ?? '未知原因'}';

  /// 消息中心的一条 → 条目。时间优先取数字的 `time`（秒），没有再解 `dateTime` 字符串。
  static _Entry _alarmEntry(Map<Object?, Object?> item) {
    final seconds = int.tryParse('${item['time'] ?? ''}');
    final at = seconds != null
        ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
        : DateTime.tryParse('${item['dateTime'] ?? ''}') ??
              DateTime.fromMillisecondsSinceEpoch(0);
    String text(Object? value) => '${value ?? ''}'.trim();
    final title = text(item['msgTitle']).isNotEmpty
        ? text(item['msgTitle'])
        : text(item['msgTypeContent']);
    return _Entry(at: at, title: title, detail: text(item['msgContent']));
  }

  static ({_PushLevel level, String? basis, bool guessed}) _gradeByTitle(
    String title,
  ) => (
    level: switch (title) {
      '设备通知' => _PushLevel.notice,
      '设备异常' => _PushLevel.severe,
      _ => _PushLevel.minor,
    },
    basis: '标题=$title',
    guessed: false,
  );

  /// 一条消息属于哪个等级（→ 哪一栏）。依次看：
  ///
  /// 1. **明文等级**：消息本身或 `extendParams`（JSON）里名字带 level / grade / severity / priority / 等级 的字段，
  ///    值是「通知 / 轻微 / 严重」或对应英文 → 直接定（`guessed = false`）；
  /// 2. 同样那些字段是**数字** → 按 [_levelCodes]（推测编码）；
  /// 3. 页面开着时收到的**设备告警** `warn56`：同一台设备、时间前后 60 秒内的那条的 `warnLevel` → 按 [_levelCodes]；
  /// 4. 消息的 `alarmType` 非 0 → 按 [_levelCodes]（这个字段是不是等级也没确认）；
  /// 5. 都没有 → 归「告警」（`basis == null`），宁可放在最显眼的一栏，也不把严重的藏进日志。
  ///
  /// [warns] 是页面开着时收到的设备告警（第 3 步用）；调试台那边没有，传空（[describeMessageGrade]）。
  static ({_PushLevel level, String? basis, bool guessed}) _gradeOf(
    Map<Object?, Object?> item,
    DateTime at, [
    List<({String devId, DateTime at, int level})> warns =
        const <({String devId, DateTime at, int level})>[],
  ]) {
    final candidates = <String, Object?>{};
    void collect(Map<Object?, Object?> source, String prefix) {
      source.forEach((key, value) {
        final name = '$key'.toLowerCase();
        if (name.contains('level') ||
            name.contains('grade') ||
            name.contains('severity') ||
            name.contains('priority') ||
            name.contains('等级')) {
          candidates['$prefix$key'] = value;
        }
      });
    }

    collect(item, '');
    final extend = item['extendParams'];
    if (extend is String && extend.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(extend);
        if (decoded is Map) collect(decoded, 'extendParams.');
      } on FormatException {
        // 不是 JSON 就当没有
      }
    } else if (extend is Map) {
      collect(extend, 'extendParams.');
    }

    const words = <_PushLevel, List<String>>{
      _PushLevel.notice: <String>['通知', '提示', 'notice', 'notification', 'info'],
      _PushLevel.minor: <String>['轻微', 'minor', 'slight', 'mild'],
      _PushLevel.severe: <String>[
        '严重',
        'severe',
        'serious',
        'critical',
        'major',
      ],
    };
    for (final entry in candidates.entries) {
      final value = '${entry.value ?? ''}'.trim().toLowerCase();
      if (value.isEmpty) continue;
      for (final level in words.keys) {
        if (words[level]!.any(value.contains)) {
          return (
            level: level,
            basis: '${entry.key}=${entry.value}',
            guessed: false,
          );
        }
      }
      final code = int.tryParse(value);
      if (code != null && _levelCodes[code] != null) {
        return (
          level: _levelCodes[code]!,
          basis: '${entry.key}=$code',
          guessed: true,
        );
      }
    }

    final devId = '${item['msgSrcId'] ?? ''}';
    for (final warn in warns.reversed) {
      if (warn.devId.isNotEmpty && devId.isNotEmpty && warn.devId != devId) {
        continue;
      }
      if (warn.at.difference(at).inSeconds.abs() > 60) continue;
      final level = _levelCodes[warn.level];
      if (level != null) {
        return (
          level: level,
          basis: 'warn56.warnLevel=${warn.level}',
          guessed: true,
        );
      }
    }

    final alarmType = int.tryParse('${item['alarmType'] ?? ''}');
    if (alarmType != null && alarmType != 0 && _levelCodes[alarmType] != null) {
      return (
        level: _levelCodes[alarmType]!,
        basis: 'alarmType=$alarmType',
        guessed: true,
      );
    }
    return (level: _PushLevel.severe, basis: null, guessed: false);
  }

  /// 联调日志用：一条消息里可能带推送等级的几个字段原样，加上判定结果。
  static String _gradeFields(
    Map<Object?, Object?> item,
    ({_PushLevel level, String? basis, bool guessed}) grade,
  ) {
    return '${item['msgTitle'] ?? item['msgTypeContent'] ?? ''} '
        'alarmType=${item['alarmType']} msgCode=${item['msgCode']} '
        'extendParams=${item['extendParams']} → ${_tabs[grade.level.tab]}(${grade.level.label})'
        '（${grade.basis == null ? '没认出等级' : '${grade.basis}${grade.guessed ? '，推测编码' : ''}'}）';
  }

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    // 消息是全取回来的，往前一年够用
    final first = today.subtract(const Duration(days: 365));
    final current = _day;
    final language = FlowerpotScope.of(context).language;
    final english = language.locale.languageCode == 'en';
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(first) ? today : current,
      firstDate: first,
      lastDate: today,
      locale: language.locale,
      helpText: english ? 'Select date' : '选择日期',
      cancelText: english ? 'Cancel' : '取消',
      confirmText: english ? 'Confirm' : '确定',
    );
    if (picked == null || !mounted) return;
    setState(() => _days[_tab] = DateUtils.dateOnly(picked));
  }

  List<_Entry> get _visible {
    final source = _entries[_tab];
    final day = _day;
    if (day == null) return source;
    return <_Entry>[
      for (final entry in source)
        if (DateUtils.isSameDay(entry.at, day)) entry,
    ];
  }

  String? get _emptyText {
    if (_loading) return '加载中…';
    final error = _error;
    if (error != null) return '没有取到：$error';
    final what = _tabs[_tab];
    return _day == null ? '暂无$what' : '当天没有$what';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final prefix = widget.keyPrefix;
    return RefreshIndicator(
      onRefresh: _reload,
      child: SingleChildScrollView(
        key: Key('$prefix-scroll-view'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MessageCategoryTabs(
              keyPrefix: prefix,
              current: _tab,
              onChanged: (index) => setState(() => _tab = index),
            ),
            const SizedBox(height: 12),
            _DateFilterCard(
              keyPrefix: prefix,
              day: _day,
              onTap: () => unawaited(_pickDay()),
              onShowAll: () => setState(() => _days[_tab] = null),
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  _emptyText ?? '',
                  key: Key('$prefix-empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MowerColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              )
            else
              for (final entry in visible) ...<Widget>[
                _MessageCard(entry: entry),
                const SizedBox(height: 12),
              ],
            if (widget.footer case final footer?) footer,
          ],
        ),
      ),
    );
  }
}

/// 列表里的一条（日志或告警）。
class _Entry {
  const _Entry({required this.at, required this.title, required this.detail});

  final DateTime at;
  final String title;
  final String detail;

  /// 稿子的写法：今天只写「10:42」，昨天「昨天 18:30」，今年「8月30日 09:12」，更早带年份。
  String timeLabel(DateTime now) {
    final hm =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final today = DateUtils.dateOnly(now);
    final day = DateUtils.dateOnly(at);
    if (day == today) return hm;
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hm';
    if (at.year == now.year) return '${at.month}月${at.day}日 $hm';
    return '${at.year}年${at.month}月${at.day}日 $hm';
  }
}

class _DateFilterCard extends StatelessWidget {
  const _DateFilterCard({
    required this.keyPrefix,
    required this.day,
    required this.onTap,
    required this.onShowAll,
  });

  final String keyPrefix;

  /// `null` = 全部日期。
  final DateTime? day;
  final VoidCallback onTap;

  /// 选了某一天时，点「全部」回到全部日期。
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('$keyPrefix-date'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MowerCard(
        color: Colors.white.withValues(alpha: .92),
        radius: 15,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '日期筛选',
                  style: TextStyle(
                    color: MowerColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (day != null) ...<Widget>[
                GestureDetector(
                  key: Key('$keyPrefix-date-all'),
                  onTap: onShowAll,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                    child: Text(
                      '全部',
                      style: TextStyle(
                        color: MowerColors.inkSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
              Text(
                day == null
                    ? '全部日期'
                    : '${day!.year}年${day!.month}月${day!.day}日',
                style: const TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 22,
                color: MowerColors.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    return MowerCard(
      color: Colors.white.withValues(alpha: .86),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.title,
                  style: const TextStyle(
                    color: MowerColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                entry.timeLabel(DateTime.now()),
                style: const TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (entry.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              entry.detail,
              style: const TextStyle(
                color: MowerColors.inkSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
