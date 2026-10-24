import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'mower_command_result.dart';
import 'mower_dp.dart';
import 'mower_fault_alarm.dart';

class MowerLogText {
  const MowerLogText(this.zh, this.en, this.shortZh, this.shortEn);
  final String zh;
  final String en;
  final String shortZh;
  final String shortEn;
  Map<String, Object> toJson() => {
    'zh': zh,
    'en': en,
    'shortZh': shortZh,
    'shortEn': shortEn,
  };
  static MowerLogText fromJson(Map data) => MowerLogText(
    data['zh'] as String,
    data['en'] as String,
    data['shortZh'] as String,
    data['shortEn'] as String,
  );
}

class MowerMachineLogEntry {
  MowerMachineLogEntry({
    required this.id,
    required this.at,
    required this.level,
    required this.group,
    required this.texts,
    Set<String>? active,
  }) : active = active ?? <String>{};
  final String id;
  final DateTime at;
  int level;
  final String group;
  final Map<String, MowerLogText> texts;
  final Set<String> active;
  bool read = false;
  DateTime? recoveredAt;
  bool get recovered => recoveredAt != null;
  String message(bool english) {
    final detailed = texts.keys.any(
      (key) =>
          key.contains('.') &&
          !key.startsWith('dp') &&
          !key.startsWith('command'),
    );
    return texts.entries
        .where((item) => !detailed || item.key != 'dp5.fault')
        .map((item) {
          final text = item.value;
          if (recovered) {
            return english ? '${text.shortEn} cleared' : '${text.shortZh}已恢复';
          }
          if (group == 'fault' && !active.contains(item.key)) {
            return english ? '${text.shortEn} cleared' : '${text.shortZh}已恢复';
          }
          return english ? text.en : text.zh;
        })
        .join('\n');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'level': level,
    'group': group,
    'read': read,
    'recoveredAt': recoveredAt?.toIso8601String(),
    'active': active.toList(),
    'texts': {for (final item in texts.entries) item.key: item.value.toJson()},
  };
  static MowerMachineLogEntry fromJson(Map data) {
    final rawTexts = data['texts'] as Map;
    final entry = MowerMachineLogEntry(
      id: data['id'] as String,
      at: DateTime.parse(data['at'] as String),
      level: (data['level'] as int).clamp(1, 3),
      group: data['group'] as String,
      texts: {
        for (final item in rawTexts.entries)
          item.key as String: MowerLogText.fromJson(item.value as Map),
      },
      active: (data['active'] as List).cast<String>().toSet(),
    );
    entry.read = data['read'] == true;
    final recovered = data['recoveredAt'];
    if (recovered is String) entry.recoveredAt = DateTime.tryParse(recovered);
    return entry;
  }
}

class _FaultEvent {
  const _FaultEvent(this.layer, this.name, this.mask, this.level, this.text);
  final String layer;
  final String name;
  final int mask;
  final int level;
  final MowerLogText text;
  String get id => '$layer.$name';
}

/// 本机 DP 边沿日志，不读取 DP18，不冒充设备本地日志或云端历史。
class MowerMachineLog extends ChangeNotifier {
  static const noticeMask = 0x00006;
  static const minorMask = 0x01038;
  static const skipMask = 0xFEFC1;
  static const capacity = 200;
  static const _faults = <_FaultEvent>[
    _FaultEvent(
      'device',
      'battery',
      1,
      3,
      MowerLogText(
        '电池异常，机器已停机',
        'Battery fault, machine stopped',
        '电池异常',
        'Battery fault',
      ),
    ),
    _FaultEvent(
      'device',
      'imu',
      2,
      3,
      MowerLogText(
        'IMU 异常，机器已停机',
        'IMU fault, machine stopped',
        'IMU 异常',
        'IMU fault',
      ),
    ),
    _FaultEvent(
      'device',
      'flash',
      4,
      3,
      MowerLogText(
        '存储异常，机器已停机',
        'Storage fault, machine stopped',
        '存储异常',
        'Storage fault',
      ),
    ),
    _FaultEvent(
      'device',
      'motor_left',
      8,
      3,
      MowerLogText(
        '左轮电机离线，机器已停机',
        'Left wheel motor offline, machine stopped',
        '左轮电机离线',
        'Left wheel motor offline',
      ),
    ),
    _FaultEvent(
      'device',
      'motor_right',
      16,
      3,
      MowerLogText(
        '右轮电机离线，机器已停机',
        'Right wheel motor offline, machine stopped',
        '右轮电机离线',
        'Right wheel motor offline',
      ),
    ),
    _FaultEvent(
      'device',
      'motor_blade',
      32,
      3,
      MowerLogText(
        '刀盘电机离线，机器已停机',
        'Blade motor offline, machine stopped',
        '刀盘电机离线',
        'Blade motor offline',
      ),
    ),
    _FaultEvent(
      'error',
      'pose',
      1,
      3,
      MowerLogText(
        '机器倾覆，请检查现场',
        'Machine tilted, check the site',
        '机器倾覆',
        'Machine tilted',
      ),
    ),
    _FaultEvent(
      'error',
      'lift',
      2,
      3,
      MowerLogText(
        '机器被抬起，已停机',
        'Machine lifted, stopped',
        '机器被抬起',
        'Machine lifted',
      ),
    ),
    _FaultEvent(
      'error',
      'boundary',
      4,
      3,
      MowerLogText(
        '边界线信号异常，机器已停机',
        'Boundary signal fault, machine stopped',
        '边界线信号异常',
        'Boundary signal fault',
      ),
    ),
    _FaultEvent(
      'error',
      'left_ocp',
      8,
      3,
      MowerLogText(
        '左轮电机过流，机器已停机',
        'Left wheel overcurrent, machine stopped',
        '左轮电机过流',
        'Left wheel overcurrent',
      ),
    ),
    _FaultEvent(
      'error',
      'left_otmp',
      16,
      3,
      MowerLogText(
        '左轮电机过温，机器已停机',
        'Left wheel overheated, machine stopped',
        '左轮电机过温',
        'Left wheel overheated',
      ),
    ),
    _FaultEvent(
      'error',
      'left_hall',
      32,
      3,
      MowerLogText(
        '左轮电机霍尔异常，机器已停机',
        'Left wheel hall error, machine stopped',
        '左轮电机霍尔异常',
        'Left wheel hall error',
      ),
    ),
    _FaultEvent(
      'error',
      'right_ocp',
      64,
      3,
      MowerLogText(
        '右轮电机过流，机器已停机',
        'Right wheel overcurrent, machine stopped',
        '右轮电机过流',
        'Right wheel overcurrent',
      ),
    ),
    _FaultEvent(
      'error',
      'right_otmp',
      128,
      3,
      MowerLogText(
        '右轮电机过温，机器已停机',
        'Right wheel overheated, machine stopped',
        '右轮电机过温',
        'Right wheel overheated',
      ),
    ),
    _FaultEvent(
      'error',
      'right_hall',
      256,
      3,
      MowerLogText(
        '右轮电机霍尔异常，机器已停机',
        'Right wheel hall error, machine stopped',
        '右轮电机霍尔异常',
        'Right wheel hall error',
      ),
    ),
    _FaultEvent(
      'error',
      'blade_otmp',
      1024,
      3,
      MowerLogText(
        '刀盘电机过温，机器已停机',
        'Blade motor overheated, machine stopped',
        '刀盘电机过温',
        'Blade motor overheated',
      ),
    ),
    _FaultEvent(
      'error',
      'blade_hall',
      2048,
      3,
      MowerLogText(
        '刀盘电机霍尔异常，机器已停机',
        'Blade hall error, machine stopped',
        '刀盘电机霍尔异常',
        'Blade hall error',
      ),
    ),
    _FaultEvent(
      'error',
      'blade_stall',
      4096,
      3,
      MowerLogText(
        '刀盘堵转（可能卡异物），机器已停机',
        'Blade stalled (possible obstruction), stopped',
        '刀盘堵转',
        'Blade stalled',
      ),
    ),
    _FaultEvent(
      'error',
      'outside',
      16384,
      3,
      MowerLogText(
        '机器在边界外，已停机',
        'Machine outside boundary, stopped',
        '机器在边界外',
        'Machine outside boundary',
      ),
    ),
    _FaultEvent(
      'error',
      'spot_out',
      32768,
      3,
      MowerLogText(
        '定点作业位置超出边界，已停机',
        'Spot position out of boundary, stopped',
        '定点作业位置超出边界',
        'Spot position out of boundary',
      ),
    ),
    _FaultEvent(
      'function',
      'trap',
      2,
      3,
      MowerLogText(
        '机器被困（陷坑），已停机',
        'Machine stuck (pit), stopped',
        '机器被困',
        'Machine stuck',
      ),
    ),
    _FaultEvent(
      'circularize',
      'trap_out',
      8,
      2,
      MowerLogText(
        '机器陷入坑洼，正在脱困',
        'Recovering from stuck',
        '机器陷入坑洼',
        'Recovering from stuck',
      ),
    ),
    _FaultEvent(
      'circularize',
      'lost_signal',
      16,
      2,
      MowerLogText(
        '丢失边界信号，正在搜索',
        'Boundary signal lost, searching',
        '丢失边界信号',
        'Boundary signal lost',
      ),
    ),
    _FaultEvent(
      'circularize',
      'outside',
      32,
      2,
      MowerLogText(
        '机器在边界外，正在找回',
        'Outside boundary, recovering',
        '机器在边界外',
        'Outside boundary',
      ),
    ),
    _FaultEvent(
      'circularize',
      'lift',
      4096,
      2,
      MowerLogText('机器被抬起', 'Machine lifted', '机器被抬起', 'Machine lifted'),
    ),
    _FaultEvent(
      'circularize',
      'rain',
      2,
      1,
      MowerLogText(
        '检测到积水，机器自动回充',
        'Water detected, returning to dock',
        '积水告警',
        'Water detected',
      ),
    ),
    _FaultEvent(
      'circularize',
      'low_charge',
      4,
      1,
      MowerLogText(
        '电量过低，机器自动回充',
        'Battery too low, returning to dock',
        '低电告警',
        'Battery too low',
      ),
    ),
  ];

  final List<MowerMachineLogEntry> _entries = [];
  List<MowerMachineLogEntry> get entries => List.unmodifiable(_entries);
  final Map<int, Object> _previous = {};
  MowerFaultAlarm? _alarm;
  MowerMachineLogEntry? _pendingFaultCommand;
  int _sequence = 0;
  int _rawLevel = 0;
  int _heldLevel = 0;
  DateTime? _holdUntil;
  bool _disposed = false;

  int get unreadCritical => _entries
      .where((entry) => entry.level == 3 && !entry.recovered && !entry.read)
      .length;
  int levelAt(DateTime now) => _holdUntil != null && now.isBefore(_holdUntil!)
      ? math.max(_heldLevel, _rawLevel)
      : _rawLevel;

  /// 快照只对齐基线；恢复、重连、查询不会凭缓存制造发生/恢复条目。
  void apply(
    Map<int, Object?> dps, {
    bool snapshot = false,
    DateTime? receivedAt,
  }) {
    if (_disposed) return;
    final at = receivedAt ?? DateTime.now();
    final freshAlarm = dps.containsKey(MowerDp.faultAlarm)
        ? MowerFaultAlarm.parse(dps[MowerDp.faultAlarm])
        : null;
    if (freshAlarm != null) {
      if (!snapshot) _faultEdges(_alarm, freshAlarm, at);
      _alarm = freshAlarm;
      if (!snapshot &&
          _pendingFaultCommand != null &&
          at.difference(_pendingFaultCommand!.at) >= Duration.zero &&
          at.difference(_pendingFaultCommand!.at) <=
              const Duration(seconds: 3)) {
        _pendingFaultCommand!.texts['command.26'] = _faultCommandText(
          freshAlarm,
        );
        _pendingFaultCommand = null;
      }
    }
    for (final dp in [
      MowerDp.status,
      MowerDp.chargingStatus,
      MowerDp.coverStatus,
      MowerDp.shutdownReport,
      MowerDp.battery,
    ]) {
      if (!dps.containsKey(dp)) continue;
      final value = _normalized(dp, dps[dp]);
      if (value == null) continue;
      final old = _previous[dp];
      _previous[dp] = value;
      if (!snapshot && old != value) _edge(dp, old, value, at);
    }
    if (dps.containsKey(MowerDp.commandResults)) {
      final result = MowerCommandResult.parse(dps[MowerDp.commandResults]);
      if (result != null) {
        final old = _previous[MowerDp.commandResults];
        _previous[MowerDp.commandResults] = result.seq;
        if (!snapshot && old != result.seq && result.code != 0) {
          final code = result.code;
          final zh = code == 26
              ? freshAlarm?.recoveryMessage ?? '故障未排除，暂未收到最新故障详情'
              : result.rejectionMessage ?? '操作未生效';
          final en = _commandEnglish(code);
          final entry = _add(
            {'command.$code': MowerLogText(zh, en, zh, en)},
            2,
            'command',
            at,
          );
          if (code == 26) {
            entry.texts['command.26'] = freshAlarm == null
                ? MowerLogText(zh, en, zh, en)
                : _faultCommandText(freshAlarm);
            _pendingFaultCommand = freshAlarm == null ? entry : null;
          }
        }
      }
    }
    final alarm = _alarm;
    var level = 0;
    if (alarm != null) {
      if ((alarm.circularize & noticeMask) != 0) level = 1;
      if ((alarm.circularize & minorMask) != 0) level = 2;
      if ((alarm.device | alarm.error | alarm.function) != 0) level = 3;
    }
    if (_previous[MowerDp.status] == 6 || _previous[MowerDp.status] == 7) {
      level = 3;
    }
    if (_previous[MowerDp.coverStatus] == false) level = math.max(level, 2);
    final current = levelAt(at);
    _rawLevel = level;
    if (level >= current) {
      _heldLevel = level;
      _holdUntil = at.add(Duration(seconds: level == 3 ? 30 : 60));
    } else if (_holdUntil == null || !at.isBefore(_holdUntil!)) {
      _heldLevel = level;
      _holdUntil = at.add(Duration(seconds: level == 3 ? 30 : 60));
    }
    notifyListeners();
  }

  void _faultEdges(MowerFaultAlarm? old, MowerFaultAlarm next, DateTime at) {
    final rising = <String, MowerLogText>{};
    var level = 0;
    for (final event in _faults) {
      final was = ((old?.layers[event.layer] ?? 0) & event.mask) != 0;
      final active = (next.layers[event.layer]! & event.mask) != 0;
      if (was && !active) _recover(event.id, at);
      if (active && !was) {
        // 同时报告抬起的两个层时只留严重原因；后续升档仍合并原条目。
        if (event.id == 'circularize.lift' && (next.error & 2) != 0) continue;
        rising[event.id] = event.text;
        level = math.max(level, event.level);
      }
    }
    if (rising.isNotEmpty) {
      final lift = rising.containsKey('error.lift');
      MowerMachineLogEntry? existing;
      if (lift) {
        for (final entry in _entries) {
          if (entry.active.contains('circularize.lift')) {
            existing = entry;
            break;
          }
        }
      }
      final entry = _add(rising, level, 'fault', at, existing: existing);
      entry.active.remove('dp5.fault');
      if (lift) {
        entry.active.remove('circularize.lift');
        entry.texts.remove('circularize.lift');
      }
    }
  }

  Object? _normalized(int dp, Object? raw) {
    if (dp == MowerDp.status) {
      return MowerDp.enumOf(
        MowerStatus.values,
        (item) => item.code,
        raw,
      )?.value;
    }
    if (dp == MowerDp.chargingStatus) {
      return MowerDp.enumOf(
        MowerChargingStatus.values,
        (item) => item.code,
        raw,
      )?.index;
    }
    if (dp == MowerDp.coverStatus || dp == MowerDp.shutdownReport) {
      if (raw is bool) return raw;
      if (raw == 1 || raw == '1' || raw == 'true') return true;
      if (raw == 0 || raw == '0' || raw == 'false') return false;
      return null;
    }
    if (raw is int && raw >= 0 && raw <= 100) return raw;
    return null;
  }

  void _edge(int dp, Object? old, Object value, DateTime at) {
    void add(
      String id,
      int level,
      String zh,
      String en, {
      String group = 'notice',
    }) => _add({id: MowerLogText(zh, en, zh, en)}, level, group, at);
    if (dp == MowerDp.status) {
      const working = [1, 3, 8, 11, 12];
      if (old == 6 && value != 6) _recover('dp5.fault', at);
      if (old == 7 && value != 7) _recover('dp5.estop', at);
      switch (value) {
        case 1:
          add('dp5.mowing', 1, '开始割草', 'Mowing started');
        case 3:
          add('dp5.spot', 1, '开始定点割草', 'Spot mowing started');
        case 8:
          add('dp5.edge', 1, '开始沿边割草', 'Edge mowing started');
        case 11:
          add('dp5.secondary', 1, '开始第二区域割草', 'Secondary area mowing started');
        // 回桩相关只记 DP5 本身（2026-10-22 用户：严格按 DP 返回显示，不擅自聚合）：
        // 4 不再按前一状态推断「作业结束」，9/10 不再推断「已回到充电桩」——回桩原因、
        // 是否触桩/充电看 DP111 与 DP117 各自的上报。
        case 4:
          add('dp5.return', 1, '正在返回充电桩', 'Returning to dock');
        // 12~14 为 2026-10-24 协议追加：回充原因由 DP5 本身给出，不再从 DP111 / DP120 推断。
        case 13:
          add(
            'dp5.return_low_power',
            1,
            '电量低，正在返回充电桩',
            'Low battery, returning to dock',
          );
        case 14:
          add(
            'dp5.return_rain',
            1,
            '检测到下雨，正在返回充电桩',
            'Rain detected, returning to dock',
          );
        case 12:
          add(
            'dp5.escaping',
            2,
            '机器陷入坑洼，正在脱困',
            'Machine stuck in a hole, escaping',
          );
        case 0:
          if (working.contains(old)) {
            add('dp5.cancel', 1, '作业已取消，机器待机', 'Work cancelled, standby');
          }
        case 6:
          add(
            'dp5.fault',
            3,
            '机器故障停机',
            'Machine stopped: fault',
            group: 'fault',
          );
        case 7:
          add(
            'dp5.estop',
            3,
            '机器被急停',
            'Emergency stop activated',
            group: 'estop',
          );
        case 9:
          add(
            'dp5.wait_charge',
            1,
            '机器在桩等待充电',
            'Waiting to charge at the dock',
          );
        case 10:
          add(
            'dp5.wait_rain',
            1,
            '机器在桩等待雨停',
            'Waiting for rain to stop at the dock',
          );
      }
    } else if (dp == MowerDp.chargingStatus) {
      if (value == 1) add('dp117.charging', 1, '已开始充电', 'Charging started');
      if (value == 2) add('dp117.full', 1, '充电完成', 'Charging complete');
      if (value == 0 && (old == 1 || old == 2)) {
        add('dp117.leave', 1, '机器已离开充电桩', 'Machine left the dock');
      }
    } else if (dp == MowerDp.battery) {
      if ((value as int) <= 35 && (old == null || (old as int) > 35)) {
        add(
          'dp13.low',
          1,
          // 只记电量本身；是否回桩以 DP5 上报为准，不预告。
          '电量低（$value%）',
          'Battery low ($value%)',
        );
      }
    } else if (dp == MowerDp.coverStatus) {
      if (old == true && value == false) {
        add('dp118.open', 2, '机器盖子被打开', 'Cover opened');
      }
      if (old == false && value == true) {
        add('dp118.close', 1, '机器盖子已关闭', 'Cover closed');
      }
    } else if (dp == MowerDp.shutdownReport) {
      if (value == true && old == false) {
        add('dp113.off', 1, '设备已关机', 'Device powered off');
      }
      if (value == false && old == true) {
        add('dp113.on', 1, '设备已开机', 'Device powered on');
      }
    }
  }

  MowerMachineLogEntry _add(
    Map<String, MowerLogText> texts,
    int level,
    String group,
    DateTime at, {
    MowerMachineLogEntry? existing,
  }) {
    if (existing == null && group == 'fault') {
      for (final entry in _entries) {
        final age = at.difference(entry.at);
        if (entry.group == group &&
            !entry.recovered &&
            age >= Duration.zero &&
            age <= const Duration(seconds: 2)) {
          existing = entry;
          break;
        }
        if (level == 2 &&
            (entry.level == 2 || entry.recovered) &&
            entry.group == group &&
            age >= Duration.zero &&
            age <= const Duration(seconds: 60) &&
            texts.keys.every(entry.texts.containsKey)) {
          existing = entry;
          break;
        }
      }
    }
    if (existing != null) {
      existing.texts.addAll(texts);
      existing.active.addAll(texts.keys);
      if (existing.texts.keys.any((id) => !id.startsWith('dp'))) {
        existing.active.remove('dp5.fault');
      }
      existing.level = math.max(level, existing.level);
      existing.recoveredAt = null;
      existing.read = false;
      return existing;
    }
    final entry = MowerMachineLogEntry(
      id: '${at.microsecondsSinceEpoch}-${_sequence++}',
      at: at,
      level: level,
      group: group,
      texts: Map.of(texts),
      active: group == 'fault' || group == 'estop'
          ? texts.keys.toSet()
          : <String>{},
    );
    _entries.insert(0, entry);
    while (_entries.length > capacity) {
      // 优先淘汰历史条目，未恢复故障仍需与下一次清位配对。
      final index = _entries.lastIndexWhere((item) => item.active.isEmpty);
      _entries.removeAt(index < 0 ? _entries.length - 1 : index);
    }
    return entry;
  }

  void _recover(String id, DateTime at) {
    for (final entry in _entries) {
      if (!entry.active.remove(id)) continue;
      if (entry.active.isEmpty) {
        entry.recoveredAt = at;
        entry.level = 1;
        entry.read = true;
      } else {
        // 合并事故部分恢复后，以仍未恢复的原因决定条目等级。
        entry.level = entry.active.fold<int>(0, (level, reason) {
          final matches = _faults.where((event) => event.id == reason);
          final activeLevel = matches.isEmpty ? 3 : matches.first.level;
          return math.max(level, activeLevel);
        });
      }
    }
  }

  MowerLogText _faultCommandText(MowerFaultAlarm alarm) {
    final names = _faults
        .where(
          (event) =>
              (event.layer == 'device' || event.layer == 'error') &&
              (alarm.layers[event.layer]! & event.mask) != 0,
        )
        .map((event) => event.text.shortEn)
        .toList();
    if (names.isEmpty &&
        alarm.error == 0 &&
        (alarm.circularize & (16 | 131072 | 262144)) != 0) {
      names.add('Boundary signal fault');
    }
    final en = names.isEmpty
        ? 'No remaining fault detected; wait 1–2 seconds and try again'
        : 'Fault not cleared: ${names.take(3).join(', ')}';
    final zh = alarm.recoveryMessage;
    return MowerLogText(zh, en, zh, en);
  }

  /// 英文文案照《拒绝理由与文案 V1.0》§6；26 由新鲜 DP111 另行定位。
  static String _commandEnglish(int code) => switch (code) {
    3 => 'Operation failed, please retry',
    16 => 'Machine is off',
    17 => 'Self-test in progress, please wait',
    18 => 'Firmware updating, please wait',
    19 => 'Machine is in emergency stop',
    21 => 'Please close the cover',
    22 => 'Machine is locked',
    23 => 'Please release the emergency stop button',
    24 => 'Searching for the boundary wire',
    25 => 'Boundary signal lost, check the wire',
    26 => 'Fault not cleared; awaiting a fresh fault report',
    32 => 'Machine is on the dock',
    33 => 'Machine is outside the boundary',
    34 => 'Battery low, charging',
    35 => 'Paused due to rain',
    48 => 'Please select a work mode first',
    49 => 'Machine is waiting at the dock',
    52 => 'Previous task was cancelled, please select again',
    53 => 'Device busy, please try again later',
    54 => 'Battery below 70%, waiting to charge at the dock',
    64 => 'Invalid parameter value',
    65 => 'Invalid data length',
    66 => 'Invalid data format',
    67 => 'Data type mismatch',
    68 => 'This parameter is read-only',
    69 => 'Please enable auto time sync first',
    70 => 'Unsupported feature',
    _ => 'Command not applied (code $code)',
  };

  void markRead({int? level, String? id}) {
    if (_disposed) return;
    for (final entry in _entries) {
      if ((level == null || entry.level == level) &&
          (id == null || entry.id == id)) {
        entry.read = true;
      }
    }
    notifyListeners();
  }

  String encode() => jsonEncode({
    'version': 1,
    'entries': _entries.map((entry) => entry.toJson()).toList(),
  });
  void restore(String? raw) {
    if (raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1 || data['entries'] is! List) {
        return;
      }
      for (final item in (data['entries'] as List).take(capacity)) {
        try {
          if (item is Map) _entries.add(MowerMachineLogEntry.fromJson(item));
        } catch (_) {
          /* 跳过损坏的本机条目，不阻断设备订阅。 */
        }
      }
    } on FormatException {
      /* 没有可恢复的本机记录。 */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
