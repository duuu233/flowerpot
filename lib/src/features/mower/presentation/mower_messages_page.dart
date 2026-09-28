import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../state.dart';
import '../../../tuya/tuya_config.dart';
import '../mower_ui.dart';
import '../mower_device.dart';
import '../mower_dp.dart';
import 'widgets/mower_bottom_nav.dart';
import 'widgets/mower_card.dart';

/// 消息通知（`割草机-消息通知.png`）。
///
/// 从设置页进来，底部导航照旧画着、停在「设置」那一栏；点「首页 / 割草计划」时
/// 先退回外壳再切到那一栏（[onTabRequested]），而不是在这一页上面再叠一层。
///
/// ## 数据从哪来（2026-09-23 联调起，稿子上那四条假消息已删）
///
/// | 分类 | 来源 |
/// | --- | --- |
/// | 日志 | 设备操作日志（DP 上报 / 下发历史）：`loadDeviceOperateLogs`，查割草机全部 DP，最近 30 天 |
/// | 提醒 | 涂鸦消息中心按这台设备取（告警档 `MSG_REPORT`，翻页取全），**推送等级是「通知」的** |
/// | 告警 | 同上，推送等级「轻微 / 严重」的，以及认不出等级的 |
///
/// 涂鸦消息中心只分告警 / 家庭 / 通知三档，平台上配的设备推送（不管哪个等级）都进告警档，
/// 所以「提醒 / 告警」只能按推送规则的等级分（2026-09-28，见 `docs/TUYA_CAPABILITY_AUDIT.md` 5.6）。
/// 等级落在消息哪个字段涂鸦文档没写：先只认明文（[_gradeOf]），认不出来的归「告警」，
/// 每条的判定依据写进联调日志，真机跑一次就知道要不要补编码。
///
/// 日期筛选：日志默认今天；提醒 / 告警默认「全部日期」，以前的推送都能看到（按设备取没有时间参数，
/// 只能全取回来再按天筛）。选某一天后可以点「全部」回到全部日期。没有记录就如实写，不编。
/// 页面开着时挂上涂鸦实时推送监听，来一条推送就重拉一次（消息中心落库比推送晚一点，所以等 2 秒）。
///
/// ## 页面底部的调试板（2026-09-18 产品追加）
///
/// 排查用：把涂鸦消息中心的每条消息**所有字段原样打印**，另可实时接收推送。
class MowerMessagesPage extends StatefulWidget {
  const MowerMessagesPage({required this.onTabRequested, super.key});

  /// 退回外壳之后要切到哪一栏。
  final ValueChanged<MowerTab> onTabRequested;

  @override
  State<MowerMessagesPage> createState() => _MowerMessagesPageState();
}

/// 三个分类（界面文案）。
const List<String> _tabs = <String>['日志', '提醒', '告警'];

/// 日志往前查多少天（日期筛选也只给选这个范围）。
const Duration _logWindow = Duration(days: 30);

class _MowerMessagesPageState extends State<MowerMessagesPage> {
  int _tab = 0;

  /// 每一栏各自的日期筛选，`null` = 全部日期：日志默认今天，提醒 / 告警默认全部（看得到以前的推送）。
  final List<DateTime?> _days = <DateTime?>[
    DateUtils.dateOnly(DateTime.now()),
    null,
    null,
  ];
  bool _loading = false;
  List<_Entry> _logs = const <_Entry>[];
  List<_Entry> _reminders = const <_Entry>[];
  List<_Entry> _alarms = const <_Entry>[];

  /// 取数失败时的一句话（原样来自接口 / 原生诊断）。提醒和告警同一个来源，共用一个。
  String? _logError;
  String? _alarmError;

  StreamSubscription<Map<String, Object?>>? _pushSub;
  Timer? _pushReload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = FlowerpotScope.of(context);
      state.logPageEntry('割草机-消息通知');
      unawaited(_reload());
      // 页面开着时收涂鸦实时推送：来一条就重拉（等 2 秒，消息中心落库比推送晚一点）。
      // SDK 的监听整个进程只注册一次，重复进页面不会重复注册（见 FlowerpotState.startPushListen）。
      unawaited(state.startPushListen());
      _pushSub = state.pushMessages.listen((_) {
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

  Future<void> _reload() async {
    final state = FlowerpotScope.of(context);
    final deviceId = MowerDevice.instance.deviceId;
    if (deviceId == null) return;
    setState(() => _loading = true);
    final dpIds = (MowerDp.identifiers.keys.toList()..sort()).join(',');
    final results = await Future.wait(<Future<Map<String, Object?>>>[
      state.loadDeviceOperateLogs(
        deviceId: deviceId,
        dpIds: dpIds,
        limit: 100,
        window: _logWindow,
      ),
      state.loadAllDeviceMessages(deviceId: deviceId),
    ]);
    if (!mounted) return;
    final logs = results[0];
    final messages = results[1];
    final reminders = <_Entry>[];
    final alarms = <_Entry>[];
    var unknown = 0;
    for (final item
        in (messages['items'] as List<Object?>?) ?? const <Object?>[]) {
      if (item is! Map) continue;
      final grade = _gradeOf(item);
      if (grade.basis == null) unknown++;
      (grade.reminder ? reminders : alarms).add(_alarmEntry(item));
    }
    reminders.sort((a, b) => b.at.compareTo(a.at));
    alarms.sort((a, b) => b.at.compareTo(a.at));
    if (messages['ok'] == true) {
      state.logNote(
        '消息通知 分档：共 ${reminders.length + alarms.length} 条 → 提醒 ${reminders.length}、告警 ${alarms.length}'
        '（其中 $unknown 条没认出推送等级，按告警）',
      );
      for (final item
          in ((messages['items'] as List<Object?>?) ?? const <Object?>[])
              .take(5)) {
        if (item is Map) state.logNote('消息通知 等级字段：${_gradeFields(item)}');
      }
    }
    setState(() {
      _loading = false;
      _logs = _logEntries(logs['raw']);
      _logError = logs['ok'] == true ? null : _reason(logs);
      _reminders = reminders;
      _alarms = alarms;
      _alarmError = messages['ok'] == true ? null : _reason(messages);
    });
  }

  /// 涂鸦平台推送规则的「推送等级」有 **通知 / 轻微 / 严重** 三档（涂鸦文档「推送设备消息」）：
  /// 通知 → 页面的「提醒」，轻微 / 严重 → 「告警」。
  ///
  /// ⚠️ 等级落在消息哪个字段、怎么编码，**涂鸦文档没写**（SDK 文档的 MessageBean 不含等级）；
  /// 解包看到的候选只有 `alarmType` / `msgCode` / `extendParams`。所以这里只认**明文**：
  /// `extendParams`（JSON）或消息本身里名字带 level / grade / severity / priority / 等级 的字段，
  /// 值是「通知 / notice / notification / info / 提醒」算提醒，「轻微 / 严重 / minor / severe …」算告警。
  /// **认不出来的一律按告警**（`basis == null`，和改之前一样），不猜数字编码——
  /// 真机拉到消息后，联调日志里有每条的这三个字段（[_gradeFields]），看了再补。
  static ({bool reminder, String? basis}) _gradeOf(Map<Object?, Object?> item) {
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

    const reminderWords = <String>['通知', '提醒', 'notice', 'notification', 'info'];
    const alarmWords = <String>['轻微', '严重', 'minor', 'severe', 'serious', 'critical', 'major'];
    for (final entry in candidates.entries) {
      final value = '${entry.value ?? ''}'.trim().toLowerCase();
      if (value.isEmpty) continue;
      if (reminderWords.any(value.contains)) {
        return (reminder: true, basis: '${entry.key}=${entry.value}');
      }
      if (alarmWords.any(value.contains)) {
        return (reminder: false, basis: '${entry.key}=${entry.value}');
      }
    }
    return (reminder: false, basis: null);
  }

  /// 联调日志用：一条消息里可能带推送等级的几个字段，原样。
  static String _gradeFields(Map<Object?, Object?> item) {
    final grade = _gradeOf(item);
    return '${item['msgTitle'] ?? item['msgTypeContent'] ?? ''} '
        'alarmType=${item['alarmType']} msgCode=${item['msgCode']} '
        'extendParams=${item['extendParams']} → '
        '${grade.reminder ? '提醒' : '告警'}（${grade.basis ?? '没认出等级'}）';
  }

  static String _reason(Map<String, Object?> data) =>
      '${data['message'] ?? (data['diagnostic'] as List<Object?>?)?.join('；') ?? '未知原因'}';

  /// 设备日志 JSON（真机 2026-09-21：`{dps:[{dpId,timeStamp(秒),timeStr,value}], dpc:[...]}`）
  /// → 条目。`dps` 是设备上报，`dpc` 是下发。
  static List<_Entry> _logEntries(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <_Entry>[];
    Object? data;
    try {
      data = jsonDecode(raw);
    } on FormatException {
      return const <_Entry>[];
    }
    if (data is! Map) return const <_Entry>[];
    final entries = <_Entry>[];
    void add(Object? list, String verb) {
      if (list is! List) return;
      for (final item in list) {
        if (item is! Map) continue;
        final dp = int.tryParse('${item['dpId']}');
        final seconds = int.tryParse('${item['timeStamp']}');
        if (dp == null || seconds == null) continue;
        entries.add(
          _Entry(
            at: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            title: 'DP$dp ${MowerDp.identifiers[dp] ?? ''}'.trim(),
            detail: '$verb ${item['value']}',
          ),
        );
      }
    }

    add(data['dps'], '上报');
    add(data['dpc'], '下发');
    entries.sort((a, b) => b.at.compareTo(a.at));
    return entries;
  }

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

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    // 日志只取了最近 30 天；提醒 / 告警是全取回来的，可以往前多选（一年够用）
    final first = today.subtract(
      _tab == 0 ? _logWindow : const Duration(days: 365),
    );
    final current = _day;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(first) ? today : current,
      firstDate: first,
      lastDate: today,
      helpText: '选择日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _days[_tab] = DateUtils.dateOnly(picked));
  }

  List<_Entry> get _visible {
    final source = switch (_tab) {
      0 => _logs,
      1 => _reminders,
      _ => _alarms,
    };
    final day = _day;
    if (day == null) return source;
    return <_Entry>[
      for (final entry in source)
        if (DateUtils.isSameDay(entry.at, day)) entry,
    ];
  }

  String? get _emptyText {
    if (_loading) return '加载中…';
    final error = _tab == 0 ? _logError : _alarmError;
    if (error != null) return '没有取到：$error';
    final what = switch (_tab) {
      0 => '记录',
      1 => '提醒',
      _ => '告警',
    };
    return _day == null ? '暂无$what' : '当天没有$what';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AppPageScaffold(
        appBar: const AppPageHeader(title: '消息通知', leading: AppBackButton()),
        body: RefreshIndicator(
          onRefresh: _reload,
          child: SingleChildScrollView(
            key: const Key('mower-messages-scroll-view'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _CategoryTabs(
                  current: _tab,
                  onChanged: (index) => setState(() => _tab = index),
                ),
                const SizedBox(height: 12),
                _DateFilterCard(
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
                      key: const Key('mower-messages-empty'),
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
                const _MessageDebugPanel(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: MowerBottomNav(
        current: MowerTab.settings,
        onTap: (tab) {
          Navigator.of(context).pop();
          if (tab != MowerTab.settings) widget.onTabRequested(tab);
        },
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

/// 日志 / 提醒 / 告警。
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // 稿子 651:2573：条高 40、内边距 4、外圆角 12 / 选中块 9。
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                key: Key('mower-messages-tab-$i'),
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == current
                        ? MowerColors.brand
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    _tabs[i],
                    style: TextStyle(
                      color: i == current ? Colors.white : MowerColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateFilterCard extends StatelessWidget {
  const _DateFilterCard({
    required this.day,
    required this.onTap,
    required this.onShowAll,
  });

  /// `null` = 全部日期。
  final DateTime? day;
  final VoidCallback onTap;

  /// 选了某一天时，点「全部」回到全部日期。
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('mower-messages-date'),
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
                  key: const Key('mower-messages-date-all'),
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
                style: const TextStyle(color: MowerColors.brand, fontSize: 15),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 22,
                color: MowerColors.brand.withValues(alpha: .9),
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

/// 涂鸦消息中心调试板（**排查设施，不是产品功能**）。
///
/// 点「拉取」→ 原生按**设备 ID** 调 `getMessageListByMsgSrcId`、把每条消息 bean 的
/// 所有无参 getter dump 上来（见 `MainActivity.deviceMessages`）。这里只负责**原样打印**：
///
/// - 每条消息的全部字段（键名里带 `type` 的会被标成品牌色，那就是问题的答案）；
/// - 拿不到时把原生的诊断行（试过哪个重载、MessageType 有哪些常量、这个类上有哪些方法）打出来；
/// - 长按整块复制，产品截图/贴给设备端都行。
///
/// ⚠️ **必须按设备取**（产品口径 2026-09-20）：标准的 `getMessageList` 是聚合结果，
/// 按它分页拿不到某台设备的全量消息 —— 之前调的就是它，打出来的东西明显不对。
/// 所以这块板上有设备 ID 输入框（默认填已绑定的第一台）和消息类型三选一
/// （`MSG_REPORT` 设备消息 / `MSG_FAMILY` 家庭 / `MSG_NOTIFY` 通知）。
class _MessageDebugPanel extends StatefulWidget {
  const _MessageDebugPanel();

  @override
  State<_MessageDebugPanel> createState() => _MessageDebugPanelState();
}

class _MessageDebugPanelState extends State<_MessageDebugPanel> {
  /// 涂鸦的消息类型（解包核对：`MessageType` 只有三个常量，`getValue()` 依次是 1 / 2 / 3）。
  ///
  /// 消息中心的三档就是**告警 / 家庭 / 通知**，设备消息推送落在告警那一档（`MSG_REPORT`），
  /// 所以默认选它。`ALL` 是本地约定：原生会把三档依次取一遍，结果里 `perType` 写明每档几条——
  /// 拉不到东西时用它判断「是这台设备没有」还是「哪一档都空」。
  static const Map<String, String> _types = <String, String>{
    'MSG_REPORT': '告警',
    'MSG_FAMILY': '家庭',
    'MSG_NOTIFY': '通知',
    'ALL': '三档都试',
  };

  /// 调试板的版本印子。**每改一次这块板就往上加一版**：贴回来的日志里有没有这行、是第几版，
  /// 一眼就能看出跑的是不是最新的包——之前两轮就卡在"看不出他跑的是哪一版"上。
  static const String _probeVersion = 'probe-v11 · 2026-09-23';

  /// 调试板默认填的设备 ID；**置空 = 取当前账号已绑定的第一台**（现在就是置空的）。
  ///
  /// 2026-09-20 曾按产品要求写死成 `6c2649322ed1365a00cadl`（后台「设备消息监控列表」里那条
  /// `text2` 挂着的设备）。2026-09-21 查清：那台是**别人账号**的设备（截图来自别人），
  /// 用它查日志回 `PERMISSION_DENIED`、查消息永远 0 条——所以改回跟着当前账号走。
  /// ⚠️ 这只是调试板的默认值，不参与任何业务逻辑。
  static const String _defaultDeviceId = '';

  /// 设备日志要查哪些 DP。真机回过 `Illegal parameter error.`，空着大概率不行，
  /// 所以默认给三个花盆一定会上报的（103 电量、105 水位、106 土壤湿度）。
  static const String _defaultDpIds = '103,105,106';

  final TextEditingController _deviceId = TextEditingController();
  final TextEditingController _dpIds = TextEditingController(
    text: _defaultDpIds,
  );

  /// 按时间窗查的起止（`yyyy-MM-dd`）。
  ///
  /// ⚠️ `getMessageListByMsgSrcId` **没有时间参数**（解包核对：四个重载多出来的只有两个
  /// 图片相关的 boolean）。整个 `IThingMessage` 上带时间的只有聚合那条
  /// `getMessageList(offset, limit, startTime, endTime, cb)`，所以这一格走的是聚合口径，
  /// 只当诊断——产品在后台某个时间段看得见消息时，用它对一对 App 这边能看见什么。
  final TextEditingController _startDay = TextEditingController();
  final TextEditingController _endDay = TextEditingController();
  bool _loadingWindow = false;
  Map<String, Object?>? _window;
  bool _loading = false;
  bool _loadingLogs = false;
  bool _prefilled = false;
  String _msgType = 'MSG_REPORT';
  Map<String, Object?>? _result;
  Map<String, Object?>? _logs;

  /// 实时推送（2026-09-23）：点一次注册，之后收到的每一条都追加在这里，最新的在前。
  Map<String, Object?>? _listen;
  bool _startingListen = false;
  StreamSubscription<Map<String, Object?>>? _pushSub;
  final List<Map<String, Object?>> _pushes = <Map<String, Object?>>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    // 默认填联调那台；没配就退回「已绑定设备里的第一台」。填错了直接改这一格。
    final today = DateTime.now();
    String day(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    _startDay.text = day(today.subtract(const Duration(days: 7)));
    _endDay.text = day(today);
    if (_defaultDeviceId.isNotEmpty) {
      _deviceId.text = _defaultDeviceId;
      _prefilled = true;
      return;
    }
    // 2026-09-23：优先填当前打开的这台割草机，没有再退回账号里第一台。
    final current = MowerDevice.instance.deviceId;
    final devices = FlowerpotScope.of(context).devices;
    if (current == null && devices.isEmpty) return;
    _deviceId.text = current ?? devices.first.id;
    _prefilled = true;
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _deviceId.dispose();
    _dpIds.dispose();
    _startDay.dispose();
    _endDay.dispose();
    super.dispose();
  }

  /// `yyyy-MM-dd` → 当天 00:00；解析不了返回 null。
  DateTime? _day(String text) => DateTime.tryParse(text.trim());

  Future<void> _loadWindow() async {
    final state = FlowerpotScope.of(context);
    final start = _day(_startDay.text);
    // 结束那天要含全天，所以加一天当右开区间。
    final endDay = _day(_endDay.text);
    if (start == null || endDay == null) {
      showAppMessage(
        context,
        '日期要写成 2026-09-18 这种格式',
        tone: AppMessageTone.info,
      );
      return;
    }
    setState(() => _loadingWindow = true);
    final data = await state.loadMessagesByTime(
      start: start,
      end: endDay.add(const Duration(days: 1)),
      deviceId: _deviceId.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loadingWindow = false;
      _window = data;
    });
  }

  /// 注册涂鸦实时推送监听，并订阅收到的推送。页面关了再进会重新订阅，
  /// 原生那边的监听整个进程只注册一次。
  Future<void> _startListen() async {
    final state = FlowerpotScope.of(context);
    setState(() => _startingListen = true);
    _pushSub ??= state.pushMessages.listen((message) {
      if (!mounted) return;
      setState(() => _pushes.insert(0, message));
    });
    final data = await state.startPushListen();
    if (!mounted) return;
    setState(() {
      _startingListen = false;
      _listen = data;
    });
  }

  /// 一条推送 → 几行文本：时间、来源、bean 类名，然后全部字段原样；
  /// `msg` 是 JSON 的话再展开一层（类型区分可能藏在里面）。
  List<String> _pushLines(Map<String, Object?> push) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      (push['receivedAt'] as num?)?.toInt() ?? 0,
    );
    String two(int v) => v.toString().padLeft(2, '0');
    final fields = (push['fields'] as Map?) ?? const <Object?, Object?>{};
    final lines = <String>[
      '${two(at.hour)}:${two(at.minute)}:${two(at.second)}  '
          '${push['source']}  ${push['beanClass'] ?? '-'}',
      for (final entry in fields.entries) '  ${entry.key} = ${entry.value}',
    ];
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value is! String || !value.trimLeft().startsWith('{')) continue;
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          lines.add('  ${entry.key} 展开：');
          decoded.forEach((key, v) => lines.add('    $key = $v'));
        }
      } on FormatException {
        // 不是 JSON 就只留原文。
      }
    }
    return lines;
  }

  /// 按 `来源/type` 数一数，一眼看出有没有类型区分。
  String get _pushTypeSummary {
    final counts = <String, int>{};
    for (final push in _pushes) {
      final fields = (push['fields'] as Map?) ?? const <Object?, Object?>{};
      final key = '${push['source']}/type=${fields['type'] ?? '-'}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries.map((e) => '${e.key} ×${e.value}').join('  ');
  }

  Future<void> _load() async {
    final state = FlowerpotScope.of(context);
    final deviceId = _deviceId.text.trim();
    if (deviceId.isEmpty) {
      showAppMessage(
        context,
        '先填设备 ID（涂鸦的 msgSrcId）',
        tone: AppMessageTone.info,
      );
      return;
    }
    setState(() => _loading = true);
    final data = await state.loadDeviceMessages(
      deviceId: deviceId,
      msgType: _msgType,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = data;
    });
  }

  /// 设备**操作日志（DP 上报历史）**——和消息中心是两个入口，这条才是「日志」。
  /// 原生原样回一段 JSON，这里也原样打印：参数顺序对不对，看报文就知道。
  Future<void> _loadLogs() async {
    final state = FlowerpotScope.of(context);
    final deviceId = _deviceId.text.trim();
    if (deviceId.isEmpty) {
      showAppMessage(
        context,
        '先填设备 ID',
        tone: AppMessageTone.info,
      );
      return;
    }
    setState(() => _loadingLogs = true);
    var data = await state.loadDeviceOperateLogs(
      deviceId: deviceId,
      dpIds: _dpIds.text.trim(),
    );
    if (!mounted) return;
    // 2026-09-21 真机：查**不属于本账号**的设备时，四种取值全是 `PERMISSION_DENIED 没权限`
    // ——这条报错本身就是答案（参数格式过了校验，卡在权限）。所以这里自动换成账号里真绑着的
    // 那台再试一次，省一个来回；两次的诊断都留着。
    final denied =
        ((data['diagnostic'] as List<Object?>?) ?? const <Object?>[])
            .join(' ')
            .contains('PERMISSION_DENIED');
    final bound = state.devices.isEmpty ? '' : state.devices.first.id;
    if (data['ok'] != true && denied && bound.isNotEmpty && bound != deviceId) {
      final retry = await state.loadDeviceOperateLogs(
        deviceId: bound,
        dpIds: _dpIds.text.trim(),
      );
      if (!mounted) return;
      data = <String, Object?>{
        ...retry,
        'diagnostic': <Object?>[
          '用 $deviceId 调是 PERMISSION_DENIED（这台不在当前账号里），'
              '自动换成已绑定的 $bound 重试：',
          ...((retry['diagnostic'] as List<Object?>?) ?? const <Object?>[]),
        ],
      };
    }
    setState(() {
      _loadingLogs = false;
      _logs = data;
    });
  }

  /// 设备日志 JSON → 读得懂的几行（原文照样保留在下面）。
  ///
  /// 真机确认的结构（2026-09-21）：`{"dpc":[],"dps":[{dpId,timeStamp(秒),timeStr,value}],
  /// "hasNext":false,"total":19}`——`dps` 是设备上报，`dpc` 看名字是下发记录（这次是空的）。
  List<String> _logLines(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <String>[];
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const <String>['（不是对象，看下面原文）'];
      final reports = (data['dps'] as List<Object?>?) ?? const <Object?>[];
      final commands = (data['dpc'] as List<Object?>?) ?? const <Object?>[];
      return <String>[
        '上报 dps ${reports.length} 条 · 下发 dpc ${commands.length} 条 · '
            'total=${data['total']} · hasNext=${data['hasNext']}',
        for (final entry in reports.take(50))
          if (entry is Map) '${entry['timeStr']}  DP${entry['dpId']} = ${entry['value']}',
      ];
    } on FormatException {
      return const <String>['（不是合法 JSON，看下面原文）'];
    }
  }

  /// 把整块面板复制到剪贴板（按钮与长按共用）。提示里带字数，省得按了不知道成没成。
  void _copyAll() {
    final text = _plainText;
    Clipboard.setData(ClipboardData(text: text));
    showAppMessage(context, '已复制调试板内容（${text.length} 字）');
  }

  /// 已绑定设备：devId → productId，用来判断某条消息是不是目标产品的。
  Map<String, String> _deviceProducts(FlowerpotState state) => <String, String>{
    for (final device in state.devices) device.id: device.productId,
  };

  /// 整块面板的纯文本。**没拉过也能复制**——至少带版本印子和现场信息，
  /// 那两行本身就是排查要的东西（跑的是哪一版包、哪个账号/家庭）。
  String get _plainText {
    final buffer = StringBuffer()
      ..writeln(_probeVersion)
      ..writeln(FlowerpotScope.of(context).sessionDiagnostics)
      ..writeln('目标设备=${_deviceId.text.trim()}  类型=$_msgType')
      ..writeln(
        '已绑定='
        '${FlowerpotScope.of(context).devices.map((d) => '${d.id}(pid=${d.productId})').join('、')}',
      )
      ..writeln(
        '目标产品 ${TuyaConfig.broadcastId}='
        '${FlowerpotScope.of(context).devices.any((d) => d.productId == TuyaConfig.broadcastId) ? '账号里有这个产品的设备' : '⚠️ 账号里没有这个产品的设备'}',
      )
      ..writeln('dpIds=${_dpIds.text.trim()}')
      ..writeln('时间窗=${_startDay.text.trim()} ~ ${_endDay.text.trim()}');
    final listen = _listen;
    if (listen != null) {
      buffer
        ..writeln('--- 实时推送 ---')
        ..writeln('ok=${listen['ok']}  已注册=${listen['registered']}');
      for (final line in (listen['diagnostic'] as List<Object?>?) ?? const <Object?>[]) {
        buffer.writeln('· $line');
      }
      buffer.writeln('收到 ${_pushes.length} 条  $_pushTypeSummary');
      for (final push in _pushes) {
        buffer.writeAll(_pushLines(push).map((line) => '$line\n'));
      }
    }
    final result = _result;
    if (result == null) {
      buffer.writeln('（还没点「拉取涂鸦消息」）');
    } else {
      buffer
        ..writeln('ok=${result['ok']}')
        ..writeln('instance=${result['instance']}')
        ..writeln('method=${result['method']}')
        ..writeln('msgSrcId=${result['msgSrcId']}')
        ..writeln('msgType=${result['msgType']}')
        ..writeln('perType=${result['perType']}')
        ..writeln('count=${result['count']}')
        ..writeln('totalCount=${result['totalCount']}');
      final items = (result['items'] as List<Object?>?) ?? const <Object?>[];
      for (var i = 0; i < items.length; i++) {
        buffer.writeln('--- 第 ${i + 1} 条 ---');
        final item = items[i];
        if (item is Map) {
          item.forEach((key, value) => buffer.writeln('$key = $value'));
        } else {
          buffer.writeln('$item');
        }
      }
      for (final line in (result['diagnostic'] as List<Object?>?) ?? const <Object?>[]) {
        buffer.writeln('· $line');
      }
    }
    final window = _window;
    if (window != null) {
      buffer
        ..writeln('--- 按时间窗（聚合口径）---')
        ..writeln(
          'ok=${window['ok']} 单位=${window['unit']} 共 ${window['count']} 条 '
          '本设备 ${window['matchedForDevice']} 条',
        );
      for (final line in (window['diagnostic'] as List<Object?>?) ?? const <Object?>[]) {
        buffer.writeln('· $line');
      }
    }
    final logs = _logs;
    if (logs != null) {
      buffer
        ..writeln('--- 设备日志（DP 上报历史）---')
        ..writeln('ok=${logs['ok']}  method=${logs['method']}  命中取值=${logs['accepted']}')
        ..writeAll(_logLines(logs['raw']).map((line) => '$line\n'))
        ..writeln('${logs['raw'] ?? logs['message'] ?? ''}');
      for (final line in (logs['diagnostic'] as List<Object?>?) ?? const <Object?>[]) {
        buffer.writeln('· $line');
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final result = _result;
    final items = (result?['items'] as List<Object?>?) ?? const <Object?>[];
    final diagnostic =
        (result?['diagnostic'] as List<Object?>?) ?? const <Object?>[];
    final products = _deviceProducts(state);
    return GestureDetector(
      onLongPress: _copyAll,
      child: MowerCard(
        key: const Key('mower-messages-debug-panel'),
        color: Colors.white.withValues(alpha: .92),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '涂鸦消息调试板',
                    style: TextStyle(
                      color: MowerColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // 手机上长按选文本很难按准，所以这里给一颗明确的复制按钮（长按整块仍然有效）。
                TextButton.icon(
                  key: const Key('mower-messages-debug-copy'),
                  onPressed: _copyAll,
                  style: TextButton.styleFrom(
                    foregroundColor: MowerColors.brand,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('复制全部', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // 版本印子 + 当前账号/家庭/设备数：贴日志时这两行最值钱——
            // 一行说明跑的是哪一版包，一行说明是不是同一个账号、同一个家庭。
            SelectableText(
              '$_probeVersion\n${state.sessionDiagnostics}',
              style: const TextStyle(
                color: MowerColors.inkSecondary,
                fontSize: 11,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '按设备 ID 拉一次涂鸦消息中心（getMessageListByMsgSrcId，默认取告警那一档），'
              '把每条消息的字段原样打印，用来确认后台配的推送等级落在哪个字段'
              '（目标产品 ${TuyaConfig.broadcastId}）。拉不到就选「三档都试」。长按可复制。',
              style: const TextStyle(
                color: MowerColors.inkSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: FilledButton(
                key: const Key('mower-messages-debug-listen'),
                onPressed: _startingListen ? null : () => unawaited(_startListen()),
                style: FilledButton.styleFrom(
                  backgroundColor: MowerColors.brand,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                child: Text(
                  _startingListen
                      ? '注册中…'
                      : _listen?['ok'] == true
                      ? '接收中（收到 ${_pushes.length} 条）'
                      : '开始接收推送（实时）',
                ),
              ),
            ),
            if (_listen != null) ...<Widget>[
              const SizedBox(height: 8),
              SelectableText(
                <String>[
                  '推送监听 ok=${_listen!['ok']}  已注册=${_listen!['registered'] ?? '-'}',
                  for (final line
                      in (_listen!['diagnostic'] as List<Object?>?) ??
                          const <Object?>[])
                    '· $line',
                  if (_pushes.isEmpty)
                    '还没收到推送'
                  else
                    '收到 ${_pushes.length} 条：$_pushTypeSummary',
                ].join('\n'),
                style: const TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 11,
                  height: 1.45,
                  fontFamily: 'monospace',
                ),
              ),
              for (final push in _pushes.take(30))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    _pushLines(push).join('\n'),
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 11,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('mower-messages-debug-device'),
              controller: _deviceId,
              // 改了就重画：下面那行「目标设备在列表里：是/否」要跟着变
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                color: MowerColors.ink,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                labelText: '设备 ID（msgSrcId）',
                isDense: true,
                border: OutlineInputBorder(),
                labelStyle: TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('mower-messages-debug-use-bound'),
                onPressed: state.devices.isEmpty
                    ? null
                    : () => setState(
                        () => _deviceId.text = state.devices.first.id,
                      ),
                style: TextButton.styleFrom(
                  foregroundColor: MowerColors.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '填账号里已绑定的那台',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            // 把已绑定设备列出来：查不到消息时，先看这台设备到底在不在当前账号里。
            SelectableText(
              products.isEmpty
                  ? '当前账号没有已绑定设备'
                  : '已绑定：'
                        '${products.entries.map((e) => '${e.key}(pid=${e.value})').join('、')}\n'
                        '目标设备在列表里：'
                        '${products.containsKey(_deviceId.text.trim()) ? '是' : '否 ← 按 msgSrcId 查不到多半是这个'}\n'
                        '目标产品 ${TuyaConfig.broadcastId}：'
                        '${products.values.contains(TuyaConfig.broadcastId) ? '有绑着这个产品的设备' : '⚠️ 账号里没有这个产品的设备——推送规则配在它上面就不会触发'}',
              style: const TextStyle(
                color: MowerColors.inkSecondary,
                fontSize: 11,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final entry in _types.entries)
                  ChoiceChip(
                    key: Key('mower-messages-debug-type-${entry.key}'),
                    label: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _msgType == entry.key,
                    onSelected: (_) => setState(() => _msgType = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: FilledButton(
                key: const Key('mower-messages-debug-load'),
                onPressed: _loading ? null : () => unawaited(_load()),
                style: FilledButton.styleFrom(
                  backgroundColor: MowerColors.brand,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                child: Text(_loading ? '拉取中…' : '拉取涂鸦消息'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('mower-messages-debug-dpids'),
              controller: _dpIds,
              style: const TextStyle(
                color: MowerColors.ink,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                labelText: '设备日志要查的 dpIds（逗号分隔）',
                isDense: true,
                border: OutlineInputBorder(),
                labelStyle: TextStyle(
                  color: MowerColors.inkSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                key: const Key('mower-messages-debug-load-logs'),
                onPressed: _loadingLogs ? null : () => unawaited(_loadLogs()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MowerColors.brand,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                child: Text(
                  _loadingLogs ? '拉取中…' : '拉设备日志（DP 上报历史）',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('mower-messages-debug-start'),
                    controller: _startDay,
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      labelText: '开始 yyyy-MM-dd',
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelStyle: TextStyle(
                        color: MowerColors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('mower-messages-debug-end'),
                    controller: _endDay,
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      labelText: '结束 yyyy-MM-dd（含当天）',
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelStyle: TextStyle(
                        color: MowerColors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                key: const Key('mower-messages-debug-load-window'),
                onPressed: _loadingWindow ? null : () => unawaited(_loadWindow()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MowerColors.brand,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                child: Text(
                  _loadingWindow ? '拉取中…' : '按时间窗拉消息（聚合口径）',
                ),
              ),
            ),
            if (_window != null) ...<Widget>[
              const SizedBox(height: 10),
              SelectableText(
                '时间窗 ok=${_window!['ok']}  单位=${_window!['unit'] ?? '-'}  '
                '共 ${_window!['count'] ?? 0} 条  本设备 ${_window!['matchedForDevice'] ?? 0} 条',
                style: const TextStyle(
                  color: MowerColors.ink,
                  fontSize: 11,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              for (final line
                  in (_window!['diagnostic'] as List<Object?>?) ??
                      const <Object?>[])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    '· $line',
                    style: const TextStyle(
                      color: MowerColors.inkSecondary,
                      fontSize: 11,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
            if (_logs != null) ...<Widget>[
              const SizedBox(height: 10),
              for (final line in _logLines(_logs!['raw']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: SelectableText(
                    line,
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 11,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              SelectableText(
                '设备日志 ok=${_logs!['ok']}  命中取值=${_logs!['accepted'] ?? '-'}\n'
                '${_logs!['raw'] ?? _logs!['message'] ?? ''}',
                style: const TextStyle(
                  color: MowerColors.ink,
                  fontSize: 11,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              for (final line
                  in (_logs!['diagnostic'] as List<Object?>?) ?? const <Object?>[])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    '· $line',
                    style: const TextStyle(
                      color: MowerColors.inkSecondary,
                      fontSize: 11,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
            if (result != null) ...<Widget>[
              const SizedBox(height: 12),
              SelectableText(
                'ok=${result['ok']}  count=${result['count'] ?? 0}'
                '  totalCount=${result['totalCount'] ?? '-'}\n'
                'msgSrcId=${result['msgSrcId'] ?? '-'}'
                '  msgType=${result['msgType'] ?? '-'}\n'
                'perType=${result['perType'] ?? '-'}\n'
                'instance=${result['instance'] ?? '-'}\n'
                'method=${result['method'] ?? '-'}',
                style: const TextStyle(
                  color: MowerColors.ink,
                  fontSize: 11,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              for (var i = 0; i < items.length; i++)
                _MessageDump(
                  index: i,
                  raw: items[i],
                  deviceProducts: products,
                ),
              if (diagnostic.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                const Text(
                  '诊断',
                  style: TextStyle(
                    color: MowerColors.inkSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final line in diagnostic)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      '· $line',
                      style: const TextStyle(
                        color: MowerColors.inkSecondary,
                        fontSize: 11,
                        height: 1.45,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 一条消息的字段 dump。键名里带 `type` 的标成品牌色——那就是要找的东西。
class _MessageDump extends StatelessWidget {
  const _MessageDump({
    required this.index,
    required this.raw,
    required this.deviceProducts,
  });

  final int index;
  final Object? raw;
  final Map<String, String> deviceProducts;

  @override
  Widget build(BuildContext context) {
    if (raw is! Map) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SelectableText('第 ${index + 1} 条：$raw'),
      );
    }
    final map = raw! as Map;
    final source = map['msgSrcId']?.toString() ?? '';
    final product = deviceProducts[source];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '第 ${index + 1} 条'
            '${product == null ? '' : '　msgSrcId 归属产品 $product'
                '${product == TuyaConfig.broadcastId ? '（就是目标产品）' : ''}'}',
            style: const TextStyle(
              color: MowerColors.brand,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final entry in map.entries)
            SelectableText(
              '${entry.key} = ${entry.value}',
              style: TextStyle(
                color: entry.key.toString().toLowerCase().contains('type')
                    ? MowerColors.brand
                    : MowerColors.ink,
                fontSize: 11,
                height: 1.5,
                fontFamily: 'monospace',
                fontWeight: entry.key.toString().toLowerCase().contains('type')
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}
