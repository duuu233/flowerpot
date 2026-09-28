import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/flowerpot_app.dart';
import '../../../../design_system/design_system.dart';
import '../../../../state.dart';
import '../../../mower/mower_ui.dart';
import '../../../mower/presentation/widgets/mower_card.dart';

/// 花盆消息通知页底部的调试台（**排查设施，不是产品功能**，2026-09-28 产品要求）。
///
/// 产品在涂鸦 IoT 后台「设备消息监控」里看到一批推送记录，要在 App 里看到它们。这里把那批记录
/// **原样写死**（[_records]），再按记录里的参数**写死**去调接口，进页面自动跑一遍：
///
/// 1. 按设备取告警档：`getMessageListByMsgSrcId(offset, limit, MSG_REPORT, 设备ID)`，翻页取全，
///    记录里出现的三台设备各一次；
/// 2. 按时间窗取：聚合的 `getMessageList(offset, limit, 开始, 结束)`（只有这条带时间），
///    记录里的两段触发时间各一次（前后各放宽 1 分钟）。
///
/// 每个接口的返回**全部字段原样打印**，最后逐条对：后台每条记录在 App 这边有没有
/// （同一台设备、触发时间前后 90 秒内、标题或内容里有同样的文字）。
///
/// ⚠️ 设备消息推送只投给**触发设备的主人 / 被分享者**，消息中心按登录账号查
/// （`docs/TUYA_CAPABILITY_AUDIT.md` 5.3.5 / 5.3.7：`6c26…cadl` 不在 `YS40301` 名下，查日志回
/// `PERMISSION_DENIED`）。记录里的用户账号是 YS391 / YS444 / YS556 开头的，App 登录的不是那个账号时
/// 查到 0 条是对的——所以最上面先打当前登录账号，并直接判一句对不对得上。
class MessageMonitorConsole extends StatefulWidget {
  const MessageMonitorConsole({super.key, this.autoRun = true});

  /// 进页面就自动按写死的参数查一遍（产品：「我要看到这些数据在 APP 页面中」）。
  final bool autoRun;

  @override
  State<MessageMonitorConsole> createState() => _MessageMonitorConsoleState();
}

/// 后台「设备消息监控」里的一条（2026-09-28 产品贴来的，原样）。
class _Record {
  const _Record({
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
  final String account;

  /// 后台显示的触发时间（北京时间）原文。
  final String triggeredAt;
  final String status;

  /// 触发时间按 +08:00 解析（后台显示的是北京时间）。
  DateTime get at =>
      DateTime.parse('${triggeredAt.replaceFirst(' ', 'T')}+08:00');
}

const String _devA = '6c81cbf961a5074c36s0pq';
const String _devB = '54ca8g6cdf16f0a8be7e9f';
const String _devC = '6c2649322ed1365a00cadl';

/// 产品贴来的 10 条（2026-09-28）。「设备ID」一列粘贴时被折行拆开，按拼回来的写；
/// 第 2 条的 `54ca8g6cdf16f0a8be7e9f` 按粘贴原样（22 位，没看到被拆开的前半截）。
/// 「消息推送名称」第 4 条粘贴里是 `ext2`、「所属产品」第 6 条是「化盆test」，都照原样。
const List<_Record> _records = <_Record>[
  _Record(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devA,
    product: '花盆test',
    account: 'YS391****',
    triggeredAt: '2026-09-23 10:47:32',
  ),
  _Record(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devB,
    product: '花盆test',
    account: 'YS444****',
    triggeredAt: '2026-09-23 10:45:32',
  ),
  _Record(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:32',
  ),
  _Record(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'ext2',
    content: 'text2',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:22',
  ),
  _Record(
    pushId: 'SMmploujUsOI26FQ',
    name: 'text3',
    content: 'text3',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:22',
  ),
  _Record(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devC,
    product: '化盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:12',
  ),
  _Record(
    pushId: 'SMmploujUsOI26FQ',
    name: 'text3',
    content: 'text3',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:12',
  ),
  _Record(
    pushId: 'GYjoVtpHsqHjpZbc',
    name: 'text2',
    content: 'text2',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:02',
  ),
  _Record(
    pushId: 'SMmploujUsOI26FQ',
    name: 'text3',
    content: 'text3',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:43:02',
  ),
  _Record(
    pushId: 'SMmploujUsOI26FQ',
    name: 'text3',
    content: 'text3',
    deviceId: _devC,
    product: '花盆test',
    account: 'YS556****',
    triggeredAt: '2026-09-18 22:42:52',
  ),
];

/// 「消息推送等级」一列粘贴里只有 5 个值，对不上 10 行，不硬配，原样列出。
const List<String> _pastedLevels = <String>['轻微', '报警', '轻微', '报警', '轻微'];

/// 两段触发时间（北京时间），前后各放宽 1 分钟。
final List<({String label, DateTime start, DateTime end})> _windows =
    <({String label, DateTime start, DateTime end})>[
      (
        label: '2026-09-18 22:41:52 ~ 22:44:32',
        start: DateTime.parse('2026-09-18T22:41:52+08:00'),
        end: DateTime.parse('2026-09-18T22:44:32+08:00'),
      ),
      (
        label: '2026-09-23 10:44:32 ~ 10:48:32',
        start: DateTime.parse('2026-09-23T10:44:32+08:00'),
        end: DateTime.parse('2026-09-23T10:48:32+08:00'),
      ),
    ];

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
  static const String _version = 'monitor-v1 · 2026-09-28';

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

  /// 按写死的参数依次调一遍（设备三台、时间窗两段），一条跑完画一条。
  Future<void> _runAll() async {
    if (_running) return;
    final state = FlowerpotScope.of(context);
    setState(() {
      _running = true;
      _calls.clear();
    });
    state.logNote('消息监控调试台 → 按后台记录写死的参数查（$_version）');
    final deviceIds = <String>{for (final record in _records) record.deviceId};
    for (final deviceId in deviceIds) {
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
    for (final window in _windows) {
      final data = await state.loadMessagesByTime(
        start: window.start,
        end: window.end,
      );
      if (!mounted) return;
      setState(
        () => _calls.add(
          _Call(
            title: '按时间窗取（聚合）getMessageList',
            params:
                '北京时间 ${window.label}（毫秒 ${window.start.millisecondsSinceEpoch}'
                ' ~ ${window.end.millisecondsSinceEpoch}，原生先按秒调）',
            data: data,
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _running = false);
    state.logNote(
      '消息监控调试台 ← 后台 ${_records.length} 条，App 查到 $_foundCount 条',
    );
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
  /// （text2 每 10 秒一条，不这样会几条记录抢同一条消息）。没配上的是 null，和 [_records] 一一对应。
  List<Map<Object?, Object?>?> get _matches {
    final used = <String>{};
    final result = <Map<Object?, Object?>?>[];
    for (final record in _records) {
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

  int get _foundCount => _matches.whereType<Map<Object?, Object?>>().length;

  /// 当前登录账号和记录里的用户账号对不对得上（后台打了码，只比前缀）。
  static String _accountVerdict(String? uid) {
    final id = (uid ?? '').trim();
    final accounts = <String>{for (final record in _records) record.account};
    if (id.isEmpty) return '⚠️ 还没登录，消息中心查不了';
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
    _Record record,
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
        '  partial=${call.data['partial'] ?? '-'}'
        '${call.data['message'] == null ? '' : '  message=${call.data['message']}'}',
    for (var i = 0; i < call.items.length; i++) ...<String>[
      '--- 第 ${i + 1} 条 ---',
      for (final entry in call.items[i].entries) '${entry.key} = ${entry.value}',
    ],
    for (final line in call.diagnostic) '· $line',
  ];

  String _plainText(FlowerpotState state) {
    final matches = _matches;
    return <String>[
      '消息监控调试台 $_version',
      state.sessionDiagnostics,
      _accountVerdict(state.user?.id),
      '已绑定：${state.devices.map((d) => '${d.id}(pid=${d.productId})').join('、')}',
      '--- 后台「设备消息监控」${_records.length} 条（写死）---',
      for (var i = 0; i < _records.length; i++)
        _recordLine(i, _records[i], matches),
      '消息推送等级（粘贴里只有 ${_pastedLevels.length} 个值，对不上行，原样）：'
          '${_pastedLevels.join('、')}',
      if (_calls.isNotEmpty)
        '对照结果：后台 ${_records.length} 条 → App 查到 $_foundCount 条',
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
                const Expanded(
                  child: Text(
                    '调试台 · 后台消息监控对照',
                    style: TextStyle(
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
              '$_version　排查用，不是产品功能。进页面按下面写死的参数自动查一遍；长按整块复制。',
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
            Text('后台「设备消息监控」${_records.length} 条（写死）', style: heading),
            const SizedBox(height: 4),
            for (var i = 0; i < _records.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  _recordLine(i, _records[i], matches),
                  key: Key('message-monitor-record-$i'),
                  style: mono,
                ),
              ),
            SelectableText(
              '消息推送等级（粘贴里只有 ${_pastedLevels.length} 个值，对不上 10 行，原样）：'
              '${_pastedLevels.join('、')}；处理状态 10 条都是「未处理」',
              style: note,
            ),
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
                '对照结果：后台 ${_records.length} 条 → App 查到 $_foundCount 条'
                '${_running ? '（还在查）' : ''}',
                key: const Key('message-monitor-summary'),
                style: heading,
              ),
            ],
            for (final call in _calls) ...<Widget>[
              const SizedBox(height: 10),
              for (final line in _callLines(call))
                SelectableText(
                  line,
                  style: line.startsWith('==')
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
