import 'dart:convert';
import 'dart:typed_data';

/// 割草机的功能点表与编解码。
///
/// 来源：`docs/割草机YUSEN Robot Mower(mz7g3yzaufvoh4ls)_09_18.xlsx`（平台导出）
/// 与 `docs/割草机Grass_Master_Automower_Tuya_DP协议_V2.2.md`（设备端 2026-09-17 逐项核对）。
///
/// ⚠️ **两份文档在 DP3 上对不上，本文件按"枚举值列表 + V2.2 协议"取**：
/// xlsx 的**说明列**写着「0 standby / 1 random(弃用) / 2 smart / 3 spot / 4 goto_charge」，
/// 而同一行的**枚举值列表**是 `standby, smart, spot, goto_charge, edge_mowing, …`——
/// 枚举**序号即传输值**，列表里根本没有 `random`，所以 smart=1、spot=2、goto_charge=3；
/// V2.2 协议（更新）也是这么写的。说明列是 `random` 还没删那一版留下的，已过期。
/// 🔶 真机联调时这条要第一个验：如果设备按说明列那套解，模式会整体错开一位。
abstract final class MowerDp {
  /// 割草机在涂鸦平台上的产品 ID。
  ///
  /// 与花盆（`TuyaConfig.productId`）区分就靠它：后台基础信息接口（`getBasicData`）的
  /// `deviceIdList` 里现在两款都有，帮助中心等按产品筛选的地方要拿对应的这一个，
  /// 不能再无脑取第一个（见 `FlowerpotState.loadFaqs(productId:)` 与 `_faqProductId`）。
  static const String productId = 'mz7g3yzaufvoh4ls';

  // ── 控制（可下发） ──────────────────────────────────────
  /// bool rw：工作开关。true=启动/继续，false=暂停（App 侧文案叫「停止」）。
  static const int switchGo = 2;

  /// enum rw：工作模式，见 [MowerMode]。App 只能下发 standby/smart/spot/goto_charge。
  static const int mode = 3;

  // ── 状态（只上报） ──────────────────────────────────────
  /// enum ro：工作状态，见 [MowerStatus]。⚠️ 与 [mode] 的枚举序**不同**，别混用。
  static const int status = 5;

  /// value ro：剩余电量 0-100 %。
  static const int battery = 13;

  /// bitmap ro：故障告警位图（13 位），文案见 [MowerFault.messages]。
  static const int fault = 18;

  /// string ro：故障告警明细 JSON（四层位图）。本轮未接。
  static const int faultAlarm = 111;

  /// enum ro：充电状态，见 [MowerChargingStatus]。
  static const int chargingStatus = 117;

  /// bool ro：盖子状态。true=合盖（可启动），false=开盖（启动前预检要拦）。
  static const int coverStatus = 118;

  // ── 计划与区域 ──────────────────────────────────────────
  /// raw rw：割草计划，88 字节，见 [MowerScheduleCodec]。
  static const int mowSchedule = 101;

  /// raw rw：区域配置，25 字节，见 [MowerZoneCodec]。
  static const int zoneConfig = 103;

  /// bool rw：恢复默认割草计划（V2.3 新增，**动作型、自复位**）。下发 true → 设备写入默认计划
  /// （每天 09:00–11:30 + 13:30–17:30，组 0「全部设置」）→ **DP101 自动上报**新计划 → 回写 false。
  /// 执行结果看 DP101，不看这条回写的 false。旧「110 割草高度」已下架，编号复用。
  static const int scheduleReset = 110;

  // ── 雨淋 ────────────────────────────────────────────────
  /// bool rw：雨滴延时开关（V2.2 新增；旧 DP102 区域开关已删除）。
  static const int rainDelaySwitch = 102;

  /// bool rw：雨淋检测开关。
  static const int rainDetectEnable = 104;

  /// value rw：雨后延迟 0-120 分钟。
  static const int rainDelay = 105;

  // ── 时间 ────────────────────────────────────────────────
  /// bool rw：时间自动同步。⚠️ 关闭时 [deviceTime] 下发会被设备拒绝。
  static const int timeSyncEnable = 106;

  /// enum rw：时区，见 [MowerTimezone]（25 值，序号 20 = UTC+8）。
  static const int timezone = 107;

  /// bool rw：夏令时开关。
  static const int dstEnable = 108;

  /// string rw：设备时间，**10 位 UTC 秒级时间戳字符串**。
  static const int deviceTime = 114;

  // ── 维护 ────────────────────────────────────────────────
  /// enum rw：机器语言，见 [MowerLanguage]（18 值）。
  static const int language = 109;

  /// string ro：升级状态。`"7"` 非待机拒绝升级 / `"20"` 升级失败，收到就弹提示（`MowerDevice`）。
  static const int otaStatus = 116;

  /// string ro：当前固件版本，如 `"1.1.3"`（2026-09-24 用户：割草机已有 DP113
  /// `fw_version`，协议 V2.3 里写的「113 割草记录已下架」是旧编号）。和花盆 DP148 同一用法：
  /// 设备「当前版本」取它，取不到才退回 SDK 的 `verSw`（`TuyaRepository._device`）。
  static const int fwVersion = 113;

  /// value rw：每次出桩作业时长上限 1-24 小时。本轮没有对应界面。
  static const int operatingTime = 119;

  /// DP 号 → 标识符，只用于日志（联调时要对着功能点表看）。
  static const Map<int, String> identifiers = <int, String>{
    switchGo: 'switch_go',
    mode: 'mode',
    status: 'status',
    battery: 'battery_percentage',
    fault: 'fault',
    mowSchedule: 'mow_schedule',
    scheduleReset: 'schedule_reset',
    rainDelaySwitch: 'rain_delay_switch',
    zoneConfig: 'zone_config',
    rainDetectEnable: 'rain_detect_enable',
    rainDelay: 'rain_delay',
    timeSyncEnable: 'time_sync_enable',
    timezone: 'timezone',
    dstEnable: 'dst_enable',
    language: 'language',
    faultAlarm: 'fault_alarm',
    deviceTime: 'device_time',
    otaStatus: 'ota_status',
    fwVersion: 'fw_version',
    chargingStatus: 'charging_status',
    coverStatus: 'cover_status',
    operatingTime: 'opearting_time',
  };

  /// 设备上报的枚举值 → 枚举项；认不出返回 null。
  ///
  /// 涂鸦上报枚举型 DP 给的是**字符串**（`smart`、`charging`），个别桥接会直接报枚举序号，
  /// 两种都认。序号即传输值（见各枚举的注释），所以按 `values[序号]` 取。
  static T? enumOf<T extends Enum>(
    List<T> values,
    String Function(T item) codeOf,
    Object? value,
  ) {
    if (value is int) {
      return value >= 0 && value < values.length ? values[value] : null;
    }
    final text = '$value'.trim();
    for (final item in values) {
      if (codeOf(item) == text) return item;
    }
    return null;
  }
}

/// DP3 工作模式。**枚举序 = 传输值**，顺序不可重排。
enum MowerMode {
  standby('standby', '待机'),
  smart('smart', '随机割草'),
  spot('spot', '定点割草'),
  gotoCharge('goto_charge', '回桩'),
  edgeMowing('edge_mowing', '沿边割草'),
  secondary('secondary', '第二区域'),
  waitCharge('wait_charge', '等待充电'),
  waitRain('wait_rain', '等待雨停');

  const MowerMode(this.code, this.label);

  /// 涂鸦下发/上报用的枚举字符串。
  final String code;
  final String label;

  /// 传输值（枚举序）。
  int get value => index;

  /// App 能下发的只有前四个，其余是设备自己的状态，下发会被拒。
  bool get sendable => index <= MowerMode.gotoCharge.index;
}

/// DP5 工作状态（只上报，12 值）。⚠️ 与 [MowerMode] 的序**不同**。
enum MowerStatus {
  standby('standby', '待机'),
  mowing('mowing', '割草中'),
  sleep('sleep', '休眠'),
  spotMowing('spot_mowing', '定点割草'),
  gotoCharge('goto_charge', '回桩中'),
  paused('paused', '已暂停'),
  fault('fault', '故障'),
  stop('stop', '急停'),
  edgeMowing('edge_mowing', '沿边割草'),
  waitCharge('wait_charge', '等待充电'),
  waitRain('wait_rain', '等待雨停'),
  secondary('secondary', '第二区域');

  const MowerStatus(this.code, this.label);

  final String code;
  final String label;
  int get value => index;
}

/// DP117 充电状态。
enum MowerChargingStatus {
  notCharging('not_charging', '未在桩'),
  charging('charging', '充电中'),
  full('full', '已充满');

  const MowerChargingStatus(this.code, this.label);

  final String code;
  final String label;
}

/// DP18 故障位图。
abstract final class MowerFault {
  /// 位 → 首页那条黄色提醒的文案（2026-09-18 产品给的原文，一字未改）。
  static const Map<int, String> messages = <int, String>{
    0: '左轮异常，请清理异物并重启。',
    1: '右轮异常，请清理异物并重启。',
    2: '电池故障，请检查连接或报修。',
    3: '机器翻倒，请将其扶正放平。',
    4: '机器被悬空，请放回地面。',
    5: '无边界信号，请检查边界线。',
    6: '刀盘负载过大，请清理缠绕物。',
    7: '刀盘过热，请暂停待冷却。',
    8: '刀盘卡死，请关机并清理。',
    9: '机器出界，请搬回边界内。',
    10: '目标点无效，请重新设置。',
    11: '机器被困，请移至平坦区域。',
    12: '刀盘电机故障，请重启或报修。',
  };

  /// 位 → 标识符，只用于日志。
  static const Map<int, String> identifiers = <int, String>{
    0: 'left_wheel',
    1: 'right_wheel',
    2: 'battery',
    3: 'pose',
    4: 'lift',
    5: 'boundary',
    6: 'blade_ocp',
    7: 'blade_otmp',
    8: 'blade_stall',
    9: 'outside',
    10: 'spot_out_boundaty',
    11: 'trap',
    12: 'blade_motor',
  };

  /// 位图里**最低的那一位**对应的文案；没有故障返回 null。
  ///
  /// 首页那条提醒只有一行，多个故障同时置位时按位序取第一个——位序就是设备端
  /// 的排列顺序（左右轮 → 电池 → 位姿…），低位是更靠近"走不动了"的硬故障。
  static String? firstMessage(int bitmap) {
    for (var bit = 0; bit < 13; bit++) {
      if (bitmap & (1 << bit) != 0) return messages[bit];
    }
    return null;
  }

  /// 位图里所有置位的标识符，日志用。
  static List<String> activeIdentifiers(int bitmap) => <String>[
    for (var bit = 0; bit < 13; bit++)
      if (bitmap & (1 << bit) != 0) identifiers[bit] ?? 'bit$bit',
  ];
}

/// DP107 时区（25 值，序号即传输值，0=UTC-12 … 12=UTC±0 … 24=UTC+12）。
///
/// ⚠️ 命名里的 A/B 不是"上午/下午"：`UTCA` 是负偏移、`UTCB` 是正偏移，
/// 所以 `UTCB8`（序号 20）才是 UTC+8。
abstract final class MowerTimezone {
  static const int count = 25;

  /// UTC±0 在枚举里的序号；偏移 = 序号 − 12。
  static const int zeroIndex = 12;

  /// 序号 → 涂鸦枚举字符串。
  static String codeOf(int index) {
    final offset = index - zeroIndex;
    return offset < 0 ? 'UTCA${-offset}' : 'UTCB$offset';
  }

  /// 序号 → 界面文案。城市名是**端上本地的一份**（时区表不来自设备，
  /// 2026-09-18 产品：没开自动设置时用前端缓存的时区数据让用户选）。
  static String labelOf(int index) {
    final offset = index - zeroIndex;
    final sign = offset < 0 ? '-' : '+';
    final hours = offset.abs().toString().padLeft(2, '0');
    final city = _cities[index] ?? '';
    return city.isEmpty ? '(UTC$sign$hours:00)' : '(UTC$sign$hours:00) $city';
  }

  /// 设备上报的枚举字符串（`UTCB8`、`UTCA5`）→ 序号；认不出返回 null。
  /// 个别桥接会直接报枚举序号（int），一并认。
  static int? indexOfCode(Object? value) {
    if (value is int) return value >= 0 && value < count ? value : null;
    final match = RegExp(r'^UTC([AB])(\d{1,2})$').firstMatch('$value'.trim());
    if (match == null) return null;
    final hours = int.parse(match.group(2)!);
    final index = match.group(1) == 'A' ? zeroIndex - hours : zeroIndex + hours;
    return index >= 0 && index < count ? index : null;
  }

  /// 手机当前时区对应的枚举序号（不足一小时的偏移按就近整小时取）。
  static int fromDeviceOffset(Duration offset) {
    final hours = (offset.inMinutes / 60).round();
    return (hours + zeroIndex).clamp(0, count - 1);
  }

  static const Map<int, String> _cities = <int, String>{
    0: '国际日期变更线西',
    1: '中途岛、萨摩亚',
    2: '夏威夷',
    3: '阿拉斯加',
    4: '洛杉矶、温哥华',
    5: '丹佛、凤凰城',
    6: '芝加哥、墨西哥城',
    7: '纽约、多伦多',
    8: '加拉加斯、圣地亚哥',
    9: '巴西利亚、布宜诺斯艾利斯',
    10: '中大西洋',
    11: '亚速尔群岛',
    12: '伦敦、里斯本',
    13: '巴黎、柏林',
    14: '雅典、开罗',
    15: '莫斯科、利雅得',
    16: '迪拜、阿布扎比',
    17: '卡拉奇、塔什干',
    18: '达卡、阿拉木图',
    19: '曼谷、雅加达',
    20: '北京、重庆、香港',
    21: '东京、首尔',
    22: '悉尼、关岛',
    23: '所罗门群岛',
    24: '奥克兰、惠灵顿',
  };
}

/// DP109 机器语言（18 值，序号即传输值）。
enum MowerLanguage {
  english('english', 'English', <String>['en']),
  german('german', 'Deutsch', <String>['de']),
  spanish('spanish', 'Español', <String>['es']),
  french('french', 'Français', <String>['fr']),
  portuguese('portuguese', 'Português', <String>['pt']),
  polish('polish', 'Polski', <String>['pl']),
  czech('czech', 'Čeština', <String>['cs']),
  dutch('dutch', 'Nederlands', <String>['nl']),
  hungarian('hungarian', 'Magyar', <String>['hu']),
  slovenian('slovenian', 'Slovenščina', <String>['sl']),
  italian('italian', 'Italiano', <String>['it']),
  danish('danish', 'Dansk', <String>['da']),
  finnish('finnish', 'Suomi', <String>['fi']),
  swedish('swedish', 'Svenska', <String>['sv']),
  romanian('romanian', 'Română', <String>['ro']),
  slovak('slovak', 'Slovenčina', <String>['sk']),
  croatian('croatian', 'Hrvatski', <String>['hr']),
  lithuanian('lithuanian', 'Lietuvių', <String>['lt']);

  const MowerLanguage(this.code, this.label, this.locales);

  final String code;
  final String label;

  /// 命中哪些手机语言码（小写，只比语言部分）。
  final List<String> locales;

  int get value => index;

  /// 按手机语言挑一个默认语种。
  ///
  /// ⚠️ **枚举里没有中文**（设备面板只有这 18 种），所以简中/繁中手机落到
  /// [english]——这不是 bug，是设备没有那个选项。2026-09-18 产品口径：
  /// DP109 没内容时按手机默认语言显示。
  static MowerLanguage forLocale(String languageCode) {
    final code = languageCode.toLowerCase();
    for (final item in MowerLanguage.values) {
      if (item.locales.contains(code)) return item;
    }
    return MowerLanguage.english;
  }
}

/// 割草计划里的一个时段（分钟数，当天零点起）。
class MowerScheduleSlot {
  const MowerScheduleSlot({
    required this.startMinutes,
    required this.endMinutes,
    this.enabled = true,
  });

  final int startMinutes;
  final int endMinutes;

  /// 时段总开关（2026-09-18 产品：修边上面再加一个总开关，分别管时段 1 / 时段 2）。
  /// 对应 DP101 每组的「时段 N 有效」字节。
  final bool enabled;

  int get durationMinutes => endMinutes - startMinutes;

  /// 设备只认 >10 分钟的时段，短的会被丢弃（V2.2 §5.1）。
  bool get validForDevice =>
      enabled && startMinutes < endMinutes && endMinutes <= 1440 && durationMinutes > 10;

  MowerScheduleSlot copyWith({int? startMinutes, int? endMinutes, bool? enabled}) =>
      MowerScheduleSlot(
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        enabled: enabled ?? this.enabled,
      );
}

/// 一天的计划：两个时段 + 沿边（修边）开关。
class MowerScheduleDay {
  const MowerScheduleDay({this.slotOne, this.slotTwo, this.edge = false});

  final MowerScheduleSlot? slotOne;
  final MowerScheduleSlot? slotTwo;

  /// DP101 每组的「沿边开关」字节：非 0 = 先绕边。
  final bool edge;

  bool get isEmpty =>
      !(slotOne?.validForDevice ?? false) && !(slotTwo?.validForDevice ?? false);

  /// 两个时段重叠了就返回那句提示（端点相接不算重叠）。
  String? get overlapMessage {
    final one = slotOne;
    final two = slotTwo;
    if (one == null || two == null || !one.enabled || !two.enabled) return null;
    if (one.startMinutes < two.endMinutes && two.startMinutes < one.endMinutes) {
      return '时段 2 与时段 1（${_hhmm(one.startMinutes)}–${_hhmm(one.endMinutes)}）重叠';
    }
    return null;
  }

  MowerScheduleDay copyWith({
    MowerScheduleSlot? slotOne,
    MowerScheduleSlot? slotTwo,
    bool? edge,
  }) => MowerScheduleDay(
    slotOne: slotOne ?? this.slotOne,
    slotTwo: slotTwo ?? this.slotTwo,
    edge: edge ?? this.edge,
  );
}

String _hhmm(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// DP101 割草计划的 88 字节编解码（8 组 × 11 字节）。
///
/// 组 0 = 全部设置（每天），组 1~7 = 周一~周日。
/// ⚠️ **界面用的是「日一二三四五六」（周日在前），DP 用的是「周一~周日」**，
/// 两者差一位，换算集中在 [groupOfWeekday] / [weekdayOfGroup]，别在页面里各算各的。
abstract final class MowerScheduleCodec {
  static const int bytes = 88;
  static const int groupSize = 11;

  /// 界面星期序（0=周日 … 6=周六）→ DP 组号（1=周一 … 7=周日）。
  static int groupOfWeekday(int weekday) => weekday == 0 ? 7 : weekday;

  /// DP 组号 → 界面星期序。
  static int weekdayOfGroup(int group) => group == 7 ? 0 : group;

  /// 按天编码：7 天各自的计划写进组 1~7，组 0 留空。
  ///
  /// ⚠️ **全量替换**：设备每次收到都会清空重建，所以这里必须把 7 天一起发，
  /// 不能只发改动的那一天（V2.2 §5.1）。
  static Uint8List encodeByDay(List<MowerScheduleDay> week) {
    final data = Uint8List(bytes);
    for (var weekday = 0; weekday < week.length && weekday < 7; weekday++) {
      final day = week[weekday];
      final offset = groupOfWeekday(weekday) * groupSize;
      _writeGroup(data, offset, day);
    }
    return data;
  }

  /// 「全部设置」形态：只填组 0，组 1~7 全 0，设备按每天执行。
  static Uint8List encodeAll(MowerScheduleDay day) {
    final data = Uint8List(bytes);
    _writeGroup(data, 0, day);
    return data;
  }

  static void _writeGroup(Uint8List data, int offset, MowerScheduleDay day) {
    final one = day.slotOne;
    final two = day.slotTwo;
    if (one != null && one.validForDevice) {
      _writeUint16(data, offset, one.startMinutes);
      _writeUint16(data, offset + 2, one.endMinutes);
      data[offset + 9] = 1;
    }
    if (two != null && two.validForDevice) {
      _writeUint16(data, offset + 4, two.startMinutes);
      _writeUint16(data, offset + 6, two.endMinutes);
      data[offset + 10] = 1;
    }
    data[offset + 8] = day.edge ? 1 : 0;
  }

  /// 小端写入（V2.2：uint16 小端）。
  static void _writeUint16(Uint8List data, int offset, int value) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
  }

  static int _readUint16(Uint8List data, int offset) =>
      data[offset] | (data[offset + 1] << 8);

  /// 解 88 字节回 7 天（界面序，0=周日）。
  ///
  /// **组 0 有效时按「每天」展开到 7 天**——设备就是这么执行的，界面照着画才不会
  /// 出现「下发了每天、界面却一天都不亮」。长度不对返回空周。
  static List<MowerScheduleDay> decode(Uint8List data) {
    final week = List<MowerScheduleDay>.filled(7, const MowerScheduleDay());
    if (data.length < bytes) return week;
    final all = _readGroup(data, 0);
    if (!all.isEmpty) {
      return List<MowerScheduleDay>.filled(7, all);
    }
    for (var group = 1; group <= 7; group++) {
      week[weekdayOfGroup(group)] = _readGroup(data, group * groupSize);
    }
    return week;
  }

  static MowerScheduleDay _readGroup(Uint8List data, int offset) {
    final oneValid = data[offset + 9] != 0;
    final twoValid = data[offset + 10] != 0;
    return MowerScheduleDay(
      slotOne: oneValid
          ? MowerScheduleSlot(
              startMinutes: _readUint16(data, offset),
              endMinutes: _readUint16(data, offset + 2),
            )
          : null,
      slotTwo: twoValid
          ? MowerScheduleSlot(
              startMinutes: _readUint16(data, offset + 4),
              endMinutes: _readUint16(data, offset + 6),
            )
          : null,
      edge: data[offset + 8] != 0,
    );
  }

  /// **逐字节解析**成几行人话（2026-09-23 联调：「把数据解析出来打印在日志上，我要对比一下」）。
  ///
  /// 和 [decode] 不同：[decode] 按设备的执行口径把无效时段丢掉；这里**原样列出每一组的全部字段**
  /// （无效时段的起止时间也列），并按 V2.2 §5.1 标出形态与会被设备丢弃 / 拒绝的时段，
  /// 对照固件或平台日志时不漏东西。
  static List<String> describe(List<int> data) {
    if (data.length != bytes) {
      return <String>['长度 ${data.length} 字节（应为 $bytes），不按 DP101 解析'];
    }
    String time(int minutes) =>
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
    int read(int offset) => data[offset] | (data[offset + 1] << 8);
    bool zero(int group) =>
        data.sublist(group * groupSize, (group + 1) * groupSize).every((b) => b == 0);
    bool anyValid(int group) =>
        data[group * groupSize + 9] != 0 || data[group * groupSize + 10] != 0;

    final daysSet = <int>[
      for (var group = 1; group <= 7; group++)
        if (!zero(group)) group,
    ];
    final lines = <String>[
      if (anyValid(0) && daysSet.isEmpty)
        '形态：全部设置（组0 有效、组1~7 全 00 → 每天按组0 执行）'
      else if (anyValid(0))
        '形态：⚠ 组0 与组1~7 混发 → 设备以组0 为准，组1~7 被忽略并清空'
      else if (daysSet.isEmpty && zero(0))
        '形态：全 00 → 清空所有计划'
      else
        '形态：按天设置（组0 无有效时段，组${daysSet.join('/')} 有内容）',
    ];
    const names = <String>['全部', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    for (var group = 0; group < 8; group++) {
      final o = group * groupSize;
      final hex = data
          .sublist(o, o + groupSize)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      if (zero(group)) {
        lines.add('组$group ${names[group]}：全 00');
        continue;
      }
      String slot(int index, int start, int end, int valid) {
        final notes = <String>[
          if (valid == 0) '无效',
          if (valid != 0 && !(start < end && end <= 1440)) '⚠ 起止不合法，设备会丢弃',
          if (valid != 0 && start < end && end - start <= 10) '⚠ ≤10 分钟，设备会丢弃',
        ];
        return '时段$index ${time(start)}–${time(end)}'
            '${notes.isEmpty ? '' : '（${notes.join('，')}）'}';
      }

      lines.add(
        '组$group ${names[group]}：'
        '${slot(1, read(o), read(o + 2), data[o + 9])}；'
        '${slot(2, read(o + 4), read(o + 6), data[o + 10])}；'
        '沿边=${data[o + 8]}　[$hex]',
      );
    }
    return lines;
  }

  /// 涂鸦 raw 型 DP 的下发值就是 base64（V2.2 §5.1）。
  static String toBase64(Uint8List data) => base64Encode(data);

  /// 日志用的十六进制串（按组分段，联调时对着协议数组看）。
  static String toHexGroups(Uint8List data) => <String>[
    for (var group = 0; group < 8; group++)
      data
          .sublist(group * groupSize, (group + 1) * groupSize)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(),
  ].join(' ');
}

/// DP103 里的一个区域（区号 / 百分比 / 出发点距离）。
class MowerZoneConfig {
  const MowerZoneConfig({
    required this.index,
    required this.percent,
    required this.meters,
  });

  /// 区号 1-5。
  final int index;

  /// 割草百分比 0-100。⚠️ **0 = 删除该区**（即使 valid=1），V2.2 §5.2。
  final int percent;

  /// 出发点距离（米，设备侧上限 200）。
  final int meters;
}

/// DP103 区域配置的 25 字节编码（5 区 × 5 字节）。
abstract final class MowerZoneCodec {
  static const int bytes = 25;
  static const int zoneSize = 5;
  static const int maxMeters = 200;

  /// Σ 有效区百分比上限；超了设备**整包拒绝**（原配置保留），所以下发前先拦。
  static const int maxTotalPercent = 100;

  static Uint8List encode(List<MowerZoneConfig> zones) {
    final data = Uint8List(bytes);
    for (final zone in zones) {
      if (zone.index < 1 || zone.index > 5) continue;
      final offset = (zone.index - 1) * zoneSize;
      final percent = zone.percent.clamp(0, 100);
      final meters = zone.meters.clamp(0, maxMeters);
      data[offset] = zone.index;
      data[offset + 1] = percent;
      data[offset + 2] = meters & 0xFF;
      data[offset + 3] = (meters >> 8) & 0xFF;
      // 百分比 0 就是删区，valid 跟着给 0，免得下发一个「有效但 0%」的自相矛盾配置。
      data[offset + 4] = percent > 0 ? 1 : 0;
    }
    return data;
  }

  static String toBase64(Uint8List data) => base64Encode(data);

  /// 解设备上报的 25 字节回 5 个区（区号 1–5，按字节位置定，与 [encode] 对称）。
  ///
  /// valid=0 或百分比 0 的区按「已删除」给 0%（V2.2 §5.2：百分比 0 = 删区）。
  /// 长度不够的区同样给 0%，页面照样能画 5 行。
  static List<MowerZoneConfig> decode(List<int> data) => <MowerZoneConfig>[
    for (var index = 1; index <= 5; index++) _readZone(data, index),
  ];

  static MowerZoneConfig _readZone(List<int> data, int index) {
    final offset = (index - 1) * zoneSize;
    if (data.length < offset + zoneSize) {
      return MowerZoneConfig(index: index, percent: 0, meters: 0);
    }
    final valid = data[offset + 4] != 0;
    return MowerZoneConfig(
      index: index,
      percent: valid ? data[offset + 1].clamp(0, 100) : 0,
      meters: data[offset + 2] | (data[offset + 3] << 8),
    );
  }

  static String toHexZones(Uint8List data) => <String>[
    for (var zone = 0; zone < 5; zone++)
      data
          .sublist(zone * zoneSize, (zone + 1) * zoneSize)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(),
  ].join(' ');
}
