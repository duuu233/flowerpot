import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../state.dart';
import '../../messages/message_category_tabs.dart';
import '../mower_machine_log.dart';
import '../mower_ui.dart';
import 'widgets/mower_card.dart';

class MowerMachineLogsView extends StatefulWidget {
  const MowerMachineLogsView({required this.deviceId, super.key});

  final String? deviceId;

  @override
  State<MowerMachineLogsView> createState() => _MowerMachineLogsViewState();
}

class _MowerMachineLogsViewState extends State<MowerMachineLogsView> {
  Future<MowerMachineLog>? _future;
  MowerMachineLog? _engine;
  FlowerpotState? _ownerState;
  Timer? _ticker;
  int _generation = 0;
  int _level = 1;
  final List<int> _ranges = [0, 0, 0];
  final List<DateTime?> _dates = [null, null, null];
  bool _pendingAlarm = false;
  bool _alarmOpen = false;
  int _critical = 0;

  bool get _english => _ownerState!.languageCode.startsWith('en');
  int get _days => _ranges[_level - 1];
  String _label(int level) => _english
      ? ['', 'Log', 'Reminder', 'Alarm'][level]
      : ['', '日志', '提醒', '告警'][level];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = FlowerpotScope.of(context);
    if (!identical(state, _ownerState)) _load(state);
  }

  @override
  void didUpdateWidget(MowerMachineLogsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) _load(_ownerState!);
  }

  void _load(FlowerpotState state) {
    final generation = ++_generation;
    _engine?.removeListener(_onLogChanged);
    _engine = null;
    _ownerState = state;
    _pendingAlarm = false;
    _critical = 0;
    final deviceId = widget.deviceId;
    _future = deviceId == null ? null : state.mowerMachineLog(deviceId);
    _future
        ?.then((engine) {
          if (!mounted || generation != _generation) return;
          _engine = engine;
          _critical = engine.unreadCritical;
          engine.addListener(_onLogChanged);
        })
        .catchError((Object _) {});
    _ticker ??= Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _tryShowAlarm();
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
        .where((entry) => entry.level == 3 && !entry.read)
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
      ).whenComplete(() => _alarmOpen = false),
    );
  }

  List<MowerMachineLogEntry> _visible(MowerMachineLog engine) {
    final now = DateTime.now();
    final selected = _dates[_level - 1];
    final start = _days == -1
        ? selected
        : _days == 0
        ? null
        : DateTime(now.year, now.month, now.day - (_days - 1));
    final end = _days == -1 && selected != null
        ? DateTime(selected.year, selected.month, selected.day + 1)
        : null;
    return engine.entries
        .where(
          (entry) =>
              entry.level == _level &&
              (start == null || !entry.at.isBefore(start)) &&
              (end == null || entry.at.isBefore(end)),
        )
        .toList();
  }

  void _selectLevel(int index) {
    setState(() => _level = index + 1);
    final engine = _engine;
    if (engine == null) return;
    for (final entry in _visible(engine)) {
      engine.markRead(id: entry.id);
    }
    unawaited(_save());
  }

  Future<void> _selectDate(int? value) async {
    if (value == null) return;
    final category = _level - 1;
    if (value != -1) {
      setState(() => _ranges[category] = value);
      return;
    }
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _dates[category] ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (!mounted || day == null) return;
    setState(() {
      _dates[category] = day;
      _ranges[category] = -1;
    });
  }

  Future<void> _save() async {
    final deviceId = widget.deviceId;
    if (deviceId != null) await _ownerState!.saveMowerMachineLog(deviceId);
  }

  String _stamp(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _timeLabel(DateTime at) {
    final local = at.toLocal();
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(local);
    final time = _stamp(local).split(' ').last.substring(0, 5);
    if (day == today) return time;
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return '${_english ? 'Yesterday' : '昨天'} $time';
    }
    if (_english) return '${local.month}/${local.day} $time';
    return '${local.year == today.year ? '' : '${local.year}年'}'
        '${local.month}月${local.day}日 $time';
  }

  Future<void> _openEntry(MowerMachineLogEntry entry) async {
    _engine?.markRead(id: entry.id);
    await _save();
    if (!mounted) return;
    await showAppNoticeDialog(
      context,
      title: _label(entry.level),
      message:
          '${entry.message(_english)}\n\n'
          '${_english ? 'App reception time' : 'APP接收时间'}：${_stamp(entry.at)}'
          '${entry.recoveredAt == null ? '' : '\n${_english ? 'Cleared at' : '恢复时间'}：${_stamp(entry.recoveredAt!)}'}',
    );
  }

  Widget _entryCard(MowerMachineLogEntry entry) {
    final message = entry.message(_english);
    final summary = entry.texts.values
        .map((text) => _english ? text.shortEn : text.shortZh)
        .join('、');
    final title = entry.recovered
        ? '$summary${_english ? ' cleared' : '已恢复'}'
        : summary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MowerCard(
        color: Colors.white.withValues(alpha: .92),
        child: InkWell(
          key: ValueKey('mower-machine-log-${entry.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => unawaited(_openEntry(entry)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: MowerColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeLabel(entry.at),
                      style: const TextStyle(
                        color: MowerColors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (!entry.read && entry.level == 3)
                      const Padding(
                        padding: EdgeInsets.only(left: 4, top: 5),
                        child: Icon(Icons.circle, size: 6, color: Colors.red),
                      ),
                  ],
                ),
                if (message != title) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(
                      color: MowerColors.inkSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _ticker?.cancel();
    _engine?.removeListener(_onLogChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deviceId == null) return const Center(child: Text('未选择设备'));
    return FutureBuilder<MowerMachineLog>(
      key: ValueKey(widget.deviceId),
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
        final selected = _dates[_level - 1];
        final entries = _visible(engine);
        return ListView(
          key: const Key('mower-machine-messages-list'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            14,
            AppSpacing.pageMargin,
            24,
          ),
          children: [
            MessageCategoryTabs(
              keyPrefix: 'mower-messages',
              current: _level - 1,
              labels: [
                for (final level in [1, 2, 3]) _label(level),
              ],
              unreadAlarm: engine.unreadCritical > 0,
              onChanged: _selectLevel,
            ),
            const SizedBox(height: 12),
            MowerCard(
              color: Colors.white.withValues(alpha: .92),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _english ? 'Date filter' : '日期筛选',
                        style: const TextStyle(
                          color: MowerColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const Key('mower-messages-date'),
                        value: _days,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: MowerColors.inkSecondary,
                          fontSize: 14,
                        ),
                        iconEnabledColor: MowerColors.inkSecondary,
                        borderRadius: BorderRadius.circular(12),
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(_english ? 'All dates' : '全部日期'),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Text(_english ? 'Today' : '今天'),
                          ),
                          DropdownMenuItem(
                            value: 7,
                            child: Text(_english ? '7 days' : '最近7天'),
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
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (engine.unreadCritical > 0 && _level != 3) ...[
              MowerCard(
                color: const Color(0xffffeeee),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _english ? 'New machine alarm' : '有新的机器告警，请检查现场',
                      ),
                    ),
                    TextButton(
                      onPressed: () => _selectLevel(2),
                      child: Text(_english ? 'View' : '查看'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    _english
                        ? 'No ${_label(_level).toLowerCase()} records'
                        : '暂无${_label(_level)}',
                    style: const TextStyle(color: MowerColors.inkSecondary),
                  ),
                ),
              ),
            for (final entry in entries) _entryCard(entry),
          ],
        );
      },
    );
  }
}
