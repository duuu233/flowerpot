import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/flowerpot_app.dart';
import '../../design_system/design_system.dart';
import '../../state.dart';
import '../mower/mower_ui.dart';
import '../mower/presentation/widgets/mower_card.dart';
import 'device_messages_view.dart';

/// 消息通知页底部的调试台（**排查设施，不是产品功能**，2026-09-28 产品要求），花盆、割草机共用，
/// **只是参数不一样**（产品：「这套逻辑照搬到割草机，只是参数不一样」）。
///
/// 按页面传进来的参数**写死**去调接口，进页面自动跑一遍：
///
/// 1. [MessageMonitorConsole.deviceIds] 每台按设备取告警档：
///    `getMessageListByMsgSrcId(offset, limit, MSG_REPORT, 设备ID)`，翻页取全；
/// 2. [MessageMonitorConsole.windows] 每段按时间窗取：聚合的 `getMessageList(offset, limit, 开始, 结束)`
///    （只有这条带时间），翻页，最多 [MessageMonitorConsole.maxWindowPages] 页。
///
/// 每个接口的返回**全部字段原样打印**，每条消息再标一句它按列表同一套规则分到哪栏
/// （[describeMessageGrade]：**日志 = 通知、提醒 = 轻微、告警 = 严重**）。给了后台「设备消息监控」
/// 里看到的记录（[MessageMonitorConsole.records]，原样写死）时，再逐条对「后台这条 App 查没查到」
/// （同一台设备、触发时间前后 90 秒内、文字相同，一条消息只配一条记录），并判当前登录账号是不是记录里的账号。
///
/// ⚠️ 设备消息推送只投给**触发设备的主人 / 被分享者**，消息中心按登录账号查
/// （`docs/TUYA_CAPABILITY_AUDIT.md` 5.3.5 / 5.3.7），登录的不是那个账号时查到 0 条是对的。
class MessageMonitorConsole extends StatefulWidget {
  const MessageMonitorConsole({
    required this.title,
    required this.deviceIds,
    required this.windows,
    super.key,
    this.records = const <MonitorRecord>[],
    this.notes = const <String>[],
    this.autoRun = true,
    this.maxWindowPages = 4,
  });

  /// 调试台标题（区分花盆 / 割草机）。
  final String title;

  /// 按设备取的设备 ID（涂鸦 `msgSrcId`），按顺序各调一次。
  final List<String> deviceIds;

  /// 按时间窗取的时间段，按顺序各调一次。
  final List<MonitorWindow> windows;

  /// 后台「设备消息监控」里看到的记录（原样写死）。空 = 不做逐条对照、不判账号。
  final List<MonitorRecord> records;

  /// 记录下面补充的说明行（粘贴里对不上的列等）。
  final List<String> notes;

  /// 进页面就自动按写死的参数查一遍（产品：「我要看到这些数据在 APP 页面中」）。
  final bool autoRun;

  /// 按时间窗取时最多翻几页（每页 50）。聚合口径里登录提醒等别的消息也在，一页不一定够。
  final int maxWindowPages;

  @override
  State<MessageMonitorConsole> createState() => _MessageMonitorConsoleState();
}

/// 按时间窗取的一段：label 是界面上写的原话（写明是北京时间还是手机本地时间），start / end 是实际传的。
typedef MonitorWindow = ({String label, DateTime start, DateTime end});

/// 后台「设备消息监控」里的一条（产品贴来的，原样）。
class MonitorRecord {
  const MonitorRecord({
    required this.pushId,
    required this.name,
    required this.content,
    required this.deviceId,
    required this.product,
    required this.account,
    required this.triggeredAt,
    this.status = '未处理',
  });

  final String pushId;
  final String name;
  final String content;
  final String deviceId;
  final String product;

  /// 后台打了码的用户账号，如 `YS556****`。
  final String account;

  /// 后台显示的触发时间（北京时间）原文，`yyyy-MM-dd HH:mm:ss`。
  final String triggeredAt;
  final String status;

  /// 触发时间按 +08:00 解析（后台显示的是北京时间）。
  DateTime get at =>
      DateTime.parse('${triggeredAt.replaceFirst(' ', 'T')}+08:00');
}

/// 一次接口调用：写死的参数 + 原样返回。
class _Call {
  const _Call({required this.title, required this.params, required this.data});

  final String title;
  final String params;
  final Map<String, Object?> data;

  List<Map<Object?, Object?>> get items => <Map<Object?, Object?>>[
    for (final item in (data['items'] as List<Object?>?) ?? const <Object?>[])
      if (item is Map) item,
  ];

  List<Object?> get diagnostic =>
      (data['diagnostic'] as List<Object?>?) ?? const <Object?>[];
}

class _MessageMonitorConsoleState extends State<MessageMonitorConsole> {
  static const String _version = 'monitor-v2 · 2026-09-28';

  bool _running = false;
  final List<_Call> _calls = <_Call>[];

  @override
  void initState() {
    super.initState();
    if (!widget.autoRun) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_runAll());
    });
  }

  /// 按写死的参数依次调一遍（先按设备、再按时间窗），一条跑完画一条。
  Future<void> _runAll() async {
    if (_running) return;
    final state = FlowerpotScope.of(context);
    setState(() {
      _running = true;
      _calls.clear();
    });
    state.logNote('${widget.title} → 按写死的参数查（$_version）');
    for (final deviceId in widget.deviceIds) {
      final data = await state.loadAllDeviceMessages(deviceId: deviceId);
      if (!mounted) return;
      setState(
        () => _calls.add(
          _Call(
            title: '按设备取告警档 getMessageListByMsgSrcId',
            params: 'msgType=MSG_REPORT msgSrcId=$deviceId（翻页取全，每页 50）',
            data: data,
          ),
        ),
      );
    }
    for (final window in widget.windows) {
      final data = await _loadWindow(state, window);
      if (!mounted) return;
      setState(
        () => _calls.add(
          _Call(
            title: '按时间窗取（聚合）getMessageList',
            params:
                '${window.label}（毫秒 ${window.start.millisecondsSinceEpoch}'
                ' ~ ${window.end.millisecondsSinceEpoch}，原生先按秒调；'
                '每页 50，最多 ${widget.maxWindowPages} 页）',
            data: data,
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _running = false);
    state.logNote('${widget.title} ← ${_summary(_matches)}');
  }

  /// 按时间窗翻页取：某页不满 50 条或出错就停，已经取到的照样返回（`pages` 写明翻了几页）。
  Future<Map<String, Object?>> _loadWindow(
    FlowerpotState state,
    MonitorWindow window,
  ) async {
    const pageSize = 50;
    final items = <Object?>[];
    var last = <String, Object?>{};
    var pages = 0;
    while (pages < widget.maxWindowPages) {
      last = await state.loadMessagesByTime(
        start: window.start,
        end: window.end,
        offset: pages * pageSize,
        limit: pageSize,
      );
      pages++;
      if (last['ok'] != true) break;
      final page = (last['items'] as List<Object?>?) ?? const <Object?>[];
      items.addAll(page);
      if (page.length < pageSize) break;
    }
    if (last['ok'] != true && items.isEmpty) return last;
    return <String, Object?>{
      ...last,
      'ok': true,
      'items': items,
      'count': items.length,
      'pages': pages,
    };
  }

  /// 一条消息的时间：数字的 `time`（秒；大于 1e11 按毫秒）优先，没有再解 `dateTime`。
  static DateTime? _itemTime(Map<Object?, Object?> item) {
    final raw = int.tryParse('${item['time'] ?? ''}');
    if (raw != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        raw > 100000000000 ? raw : raw * 1000,
      );
    }
    return DateTime.tryParse('${item['dateTime'] ?? ''}');
  }

  /// 同一条消息在「按设备」和「按时间窗」两次调用里各出现一次，按这几样认成同一条。
  static String _itemKey(Map<Object?, Object?> item) =>
      '${item['id'] ?? item['msgId'] ?? ''}|${item['time'] ?? item['dateTime'] ?? ''}'
      '|${item['msgSrcId'] ?? ''}|${item['msgTitle'] ?? ''}';

  /// 逐条对：后台每条记录在 App 查到的消息里对应哪一条——同一台设备（消息没带设备 ID 时不看设备）、
  /// 触发时间前后 90 秒内、标题或内容里有同样的文字，挑时间最近的；**一条消息只配一条记录**
  /// （text2 每 10 秒一条，不这样会几条记录抢同一条消息）。没配上的是 null，和 records 一一对应。
  List<Map<Object?, Object?>?> get _matches {
    final used = <String>{};
    final result = <Map<Object?, Object?>?>[];
    for (final record in widget.records) {
      Map<Object?, Object?>? best;
      var bestGap = 91;
      for (final call in _calls) {
        for (final item in call.items) {
          if (used.contains(_itemKey(item))) continue;
          final source = '${item['msgSrcId'] ?? ''}';
          if (source.isNotEmpty && source != record.deviceId) continue;
          final at = _itemTime(item);
          if (at == null) continue;
          final gap = at.difference(record.at).inSeconds.abs();
          if (gap >= bestGap) continue;
          final text = '${item['msgTitle'] ?? ''} ${item['msgContent'] ?? ''}';
          if (!text.contains(record.content)) continue;
          best = item;
          bestGap = gap;
        }
      }
      if (best != null) used.add(_itemKey(best));
      result.add(best);
    }
    return result;
  }

  /// 当前登录账号；给了后台记录时，再判和记录里的用户账号对不对得上（后台打了码，只比前缀）。
  String _accountVerdict(String? uid) {
    final id = (uid ?? '').trim();
    if (id.isEmpty) return '⚠️ 还没登录，消息中心查不了';
    if (widget.records.isEmpty) {
      return '当前账号 $id（消息中心只看得到这个账号收到的推送）';
    }
    final accounts = <String>{
      for (final record in widget.records) record.account,
    };
    final hit = accounts.where(
      (account) => id.startsWith(account.replaceAll('*', '')),
    );
    if (hit.isNotEmpty) {
      return '✓ 当前账号 $id 对得上记录里的 ${hit.join('、')}';
    }
    return '⚠️ 当前账号 $id 不是记录里的 ${accounts.join(' / ')}：设备消息只投给触发设备的'
        '主人 / 被分享者，用这个账号查不到属正常；要看得用对应账号登录 App';
  }

  String _recordLine(
    int index,
    MonitorRecord record,
    List<Map<Object?, Object?>?> matches,
  ) {
    final match = _calls.isEmpty ? null : matches[index];
    final verdict = _calls.isEmpty
        ? ''
        : match == null
        ? '  → ✗ App 没查到'
        : '  → ✓ App 查到（${match['msgTitle'] ?? ''} '
              '${match['dateTime'] ?? match['time'] ?? ''}）';
    return '#${index + 1} ${record.triggeredAt}  ${record.pushId}  '
        '名称=${record.name} 内容=${record.content}\n'
        '    设备=${record.deviceId}  ${record.product}  ${record.account}  '
        '${record.status}$verdict';
  }

  static List<String> _callLines(_Call call) => <String>[
    '== ${call.title}',
    '参数：${call.params}',
    'ok=${call.data['ok']}  count=${call.data['count'] ?? 0}'
        '  totalCount=${call.data['totalCount'] ?? '-'}'
        '  unit=${call.data['unit'] ?? '-'}'
        '  pages=${call.data['pages'] ?? '-'}'
        '  partial=${call.data['partial'] ?? '-'}'
        '${call.data['message'] == null ? '' : '  message=${call.data['message']}'}',
    for (var i = 0; i < call.items.length; i++) ...<String>[
      '--- 第 ${i + 1} 条 → 分到 ${describeMessageGrade(call.items[i])} ---',
      for (final entry in call.items[i].entries) '${entry.key} = ${entry.value}',
    ],
    for (final line in call.diagnostic) '· $line',
  ];

  /// 一行结论：调了几次、共返回几条；有后台记录时再加「后台 N 条 → App 查到 M 条」。
  String _summary(List<Map<Object?, Object?>?> matches) {
    final total = _calls.fold<int>(0, (sum, call) => sum + call.items.length);
    final found = matches.whereType<Map<Object?, Object?>>().length;
    return '查询结果：${_calls.length} 次调用共返回 $total 条'
        '${widget.records.isEmpty ? '' : '；后台 ${widget.records.length} 条 → App 查到 $found 条'}'
        '${_running ? '（还在查）' : ''}';
  }

  String _plainText(FlowerpotState state) {
    final matches = _matches;
    return <String>[
      '${widget.title} $_version',
      state.sessionDiagnostics,
      _accountVerdict(state.user?.id),
      '已绑定：${state.devices.map((d) => '${d.id}(pid=${d.productId})').join('、')}',
      for (final id in widget.deviceIds) '按设备取：$id',
      for (final window in widget.windows) '按时间窗取：${window.label}',
      if (widget.records.isNotEmpty) ...<String>[
        '--- 后台「设备消息监控」${widget.records.length} 条（写死）---',
        for (var i = 0; i < widget.records.length; i++)
          _recordLine(i, widget.records[i], matches),
      ],
      ...widget.notes,
      if (_calls.isNotEmpty) _summary(matches),
      for (final call in _calls) ..._callLines(call),
    ].join('\n');
  }

  void _copyAll() {
    final text = _plainText(FlowerpotScope.of(context));
    Clipboard.setData(ClipboardData(text: text));
    showAppMessage(context, '已复制调试台内容（${text.length} 字）');
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    const mono = TextStyle(
      color: MowerColors.ink,
      fontSize: 11,
      height: 1.5,
      fontFamily: 'monospace',
    );
    const note = TextStyle(
      color: MowerColors.inkSecondary,
      fontSize: 11,
      height: 1.45,
      fontFamily: 'monospace',
    );
    const heading = TextStyle(
      color: MowerColors.brand,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final bound = state.devices.isEmpty
        ? '（无）'
        : state.devices.map((d) => '${d.id}(pid=${d.productId})').join('、');
    final matches = _matches;
    final params = <String>[
      for (final id in widget.deviceIds) '按设备取：$id',
      for (final window in widget.windows) '按时间窗取：${window.label}',
    ];
    return GestureDetector(
      onLongPress: _copyAll,
      child: MowerCard(
        key: const Key('message-monitor-console'),
        color: Colors.white.withValues(alpha: .92),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: MowerColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('message-monitor-copy'),
                  onPressed: _copyAll,
                  style: TextButton.styleFrom(
                    foregroundColor: MowerColors.brand,
                  ),
                  child: const Text('复制'),
                ),
              ],
            ),
            const Text(
              '$_version　排查用，不是产品功能。进页面按下面写死的参数自动查一遍；长按整块复制。'
              '每条消息标了按列表规则分到哪栏：日志 = 通知、提醒 = 轻微、告警 = 严重。',
              style: note,
            ),
            const SizedBox(height: 8),
            SelectableText(state.sessionDiagnostics, style: mono),
            SelectableText(
              _accountVerdict(state.user?.id),
              key: const Key('message-monitor-account'),
              style: mono,
            ),
            SelectableText('已绑定：$bound', style: note),
            const SizedBox(height: 10),
            const Text('写死的参数', style: heading),
            const SizedBox(height: 4),
            SelectableText(
              params.isEmpty ? '（没有可查的设备 / 时间段）' : params.join('\n'),
              key: const Key('message-monitor-params'),
              style: mono,
            ),
            if (widget.records.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '后台「设备消息监控」${widget.records.length} 条（写死）',
                style: heading,
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < widget.records.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText(
                    _recordLine(i, widget.records[i], matches),
                    key: Key('message-monitor-record-$i'),
                    style: mono,
                  ),
                ),
            ],
            for (final line in widget.notes) SelectableText(line, style: note),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                key: const Key('message-monitor-run'),
                onPressed: _running ? null : () => unawaited(_runAll()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MowerColors.brand,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                child: Text(_running ? '查询中…' : '按写死的参数重新查'),
              ),
            ),
            if (_calls.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              SelectableText(
                _summary(matches),
                key: const Key('message-monitor-summary'),
                style: heading,
              ),
            ],
            for (final call in _calls) ...<Widget>[
              const SizedBox(height: 10),
              for (final line in _callLines(call))
                SelectableText(
                  line,
                  style: line.startsWith('==') || line.startsWith('---')
                      ? heading
                      : line.startsWith('·')
                      ? note
                      : mono,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
