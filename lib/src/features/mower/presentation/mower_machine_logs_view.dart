import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../state.dart';
import '../mower_machine_log.dart';
import '../mower_ui.dart';
import 'widgets/mower_card.dart';

class MowerMachineLogsView extends StatefulWidget {
  const MowerMachineLogsView({
    required this.deviceId,
    this.cloudFooter,
    super.key,
  });
  final String? deviceId;
  final Widget? cloudFooter;
  @override
  State<MowerMachineLogsView> createState() => _MowerMachineLogsViewState();
}

class _MowerMachineLogsViewState extends State<MowerMachineLogsView> {
  Future<MowerMachineLog>? _future;
  MowerMachineLog? _engine;
  Timer? _ticker;
  int _level = 1;
  int _days = 0;
  final List<DateTime?> _dates = [null, null, null];
  bool _pendingAlarm = false;
  bool _alarmOpen = false;
  int _critical = 0;
  bool _showCloud = false;
  FlowerpotState get _state => FlowerpotScope.of(context);
  bool get _english => _state.languageCode.startsWith('en');
  String _label(int level) => _english
      ? ['', 'Log', 'Reminder', 'Alarm'][level]
      : ['', '日志', '提醒', '告警'][level];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null || widget.deviceId == null) return;
    _future = _state.mowerMachineLog(widget.deviceId!);
    _future!
        .then((engine) {
          if (!mounted) return;
          _engine = engine;
          _critical = engine.unreadCritical;
          engine.addListener(_onLogChanged);
        })
        .catchError((Object _) {});
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() {});
        _tryShowAlarm();
      }
    });
  }

  void _onLogChanged() {
    if (!mounted) return;
    final critical = _engine?.unreadCritical ?? 0;
    if (critical > _critical) {
      unawaited(SystemSound.play(SystemSoundType.alert));
      _pendingAlarm = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryShowAlarm());
    }
    _critical = critical;
    setState(() {});
  }

  void _tryShowAlarm() {
    if (!mounted ||
        !_pendingAlarm ||
        _alarmOpen ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final entries = _engine?.entries
        .where((e) => e.level == 3 && !e.read)
        .toList();
    if (entries == null || entries.isEmpty) {
      _pendingAlarm = false;
      return;
    }
    _pendingAlarm = false;
    _alarmOpen = true;
    unawaited(
      showAppNoticeDialog(
        context,
        title: _english ? 'Machine alarm' : '设备告警',
        message: entries.first.message(_english),
        confirmLabel: _english ? 'Acknowledged' : '我已处理',
        icon: Icons.warning_amber_rounded,
        tone: AppDialogTone.danger,
      ).whenComplete(() {
        _alarmOpen = false;
      }),
    );
  }

  Future<void> _selectDate(int? value) async {
    if (value == null) return;
    if (value != -1) {
      setState(() => _days = value);
      return;
    }
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _dates[_level - 1] ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (!mounted || day == null) return;
    setState(() {
      _dates[_level - 1] = day;
      _days = -1;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _engine?.removeListener(_onLogChanged);
    super.dispose();
  }

  Future<void> _read({String? id, int? level}) async {
    _engine?.markRead(id: id, level: level);
    final deviceId = widget.deviceId;
    if (deviceId != null) await _state.saveMowerMachineLog(deviceId);
  }

  String _stamp(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deviceId == null) return const Center(child: Text('未选择设备'));
    return FutureBuilder<MowerMachineLog>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              _english
                  ? 'Unable to load local machine logs'
                  : '本机机器日志读取失败，请重新进入页面',
            ),
          );
        }
        final engine = snapshot.data;
        if (engine == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        final selected = _dates[_level - 1];
        final end = _days == -1 && selected != null
            ? DateTime(selected.year, selected.month, selected.day + 1)
            : null;
        final start = _days == -1
            ? selected
            : _days == 0
            ? null
            : _days == 1
            ? DateTime(now.year, now.month, now.day)
            : now.subtract(Duration(days: _days));
        final entries = engine.entries
            .where(
              (entry) =>
                  entry.level == _level &&
                  (start == null || !entry.at.isBefore(start)) &&
                  (end == null || entry.at.isBefore(end)),
            )
            .toList();
        final current = engine.levelAt(now);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Column(
                children: [
                  Text(
                    _english
                        ? 'Reconstructed from DP reports received by this app. '
                              'Events while offline are unavailable.'
                        : '根据本机接收的 DP 上报生成；离线期间的事件无法补齐。',
                    style: const TextStyle(
                      fontSize: 11,
                      color: MowerColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final level in [1, 2, 3])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() => _level = level);
                                unawaited(_read(level: level));
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _level == level
                                    ? MowerColors.softFill
                                    : null,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                              ),
                              child: Text(
                                '${_label(level)}${level == 3 && engine.unreadCritical > 0 ? ' (${engine.unreadCritical})' : ''}',
                                key: Key('mower-messages-tab-${level - 1}'),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _english
                              ? 'Current: ${current == 0 ? 'Normal' : _label(current)}'
                              : '当前等级：${current == 0 ? '正常' : _label(current)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownButton<int>(
                        key: const Key('mower-messages-date'),
                        value: _days,
                        items: [
                          DropdownMenuItem(
                            value: 1,
                            child: Text(_english ? 'Today' : '今天'),
                          ),
                          DropdownMenuItem(
                            value: 7,
                            child: Text(_english ? '7 days' : '最近7天'),
                          ),
                          DropdownMenuItem(
                            value: 0,
                            child: Text(_english ? 'All dates' : '全部日期'),
                          ),
                          DropdownMenuItem(
                            value: -1,
                            child: Text(
                              _days == -1 && selected != null
                                  ? _stamp(selected).split(' ').first
                                  : (_english ? 'Choose date' : '选择日期'),
                            ),
                          ),
                        ],
                        onChanged: _selectDate,
                      ),
                    ],
                  ),
                  if (engine.unreadCritical > 0 && _level != 3)
                    Semantics(
                      liveRegion: true,
                      child: MowerCard(
                        color: const Color(0xffffeeee),
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _english
                                    ? 'New machine alarm'
                                    : '有新的机器告警，请检查现场',
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() => _level = 3);
                                unawaited(_read(level: 3));
                              },
                              child: Text(_english ? 'View' : '查看'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          _english
                              ? 'No ${_label(_level).toLowerCase()} records'
                              : '暂无${_label(_level)}',
                        ),
                      ),
                    ),
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MowerCard(
                        padding: const EdgeInsets.all(12),
                        child: InkWell(
                          onTap: () async {
                            await _read(id: entry.id);
                            if (!context.mounted) return;
                            await showAppNoticeDialog(
                              context,
                              title: _label(entry.level),
                              message:
                                  '${entry.message(_english)}\n\n${_english ? 'App reception time' : 'APP接收时间'}：'
                                  '${_stamp(entry.at)}${entry.recoveredAt == null ? '' : '\n${_english ? 'Cleared at' : '恢复时间'}：${_stamp(entry.recoveredAt!)}'}',
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _stamp(entry.at),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: MowerColors.inkSecondary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    entry.recovered
                                        ? (_english ? 'Cleared' : '已恢复')
                                        : _label(entry.level),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: entry.level == 3
                                          ? Colors.red
                                          : MowerColors.brand,
                                    ),
                                  ),
                                  if (!entry.read && entry.level == 3)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.circle,
                                        size: 6,
                                        color: Colors.red,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                entry.message(_english),
                                key: ValueKey('mower-machine-log-${entry.id}'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (widget.cloudFooter != null)
                    ExpansionTile(
                      title: Text(
                        _english ? 'Cloud push diagnostics' : '云端推送调试',
                      ),
                      onExpansionChanged: (value) =>
                          setState(() => _showCloud = value),
                      children: [if (_showCloud) widget.cloudFooter!],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
