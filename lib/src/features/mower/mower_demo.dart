import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// 割草机静态页面的总闸。
///
/// **2026-09-18 产品要求：先在「搜索设备」列表里放一条固定的割草机数据，点进去
/// 就能把割草机那套 UI 逐页看完。** 这一轮只做静态页——不连 SDK、不发 DP、不读
/// 后端，页面上的每一个数字都来自这个文件。
///
/// ⚠️ **这是门禁，不是硬编码进动线。** [enabled] 翻成 `false`，搜索页那条静态行
/// 立刻消失，其余代码原样留着；真的割草机能被扫到之后，把 [MowerDemoDevice] 换成
/// 真实设备模型即可，页面层不用重写。
abstract final class MowerDemo {
  /// 搜索页要不要列那条静态的割草机。
  ///
  /// ⚠️ **不是 `const`**：用例要能两头都验（列着时点得进去、关掉时列表里没有它）。
  /// 用例改过必须在 `tearDown` 里 [reset] 回来。
  static bool enabled = _enabledDefault;

  static const bool _enabledDefault = true;

  static void reset() => enabled = _enabledDefault;
}

/// 设计稿里这台割草机的全部固定数据（`docs/UI/v2/割草机/`）。
///
/// 名字、型号、SN、电量、计划、消息……稿子上写的是什么这里就是什么，不做任何
/// "看起来更真实"的加工：这一轮交付的是**版式**，数字对不对由产品看稿子定。
abstract final class MowerDemoDevice {
  static const String name = 'YSmower-01';
  static const String model = 'YM-1200';
  static const String serialNumber = 'YM202608240018';

  /// 首页那圈电量环：默认态 78%（`割草机-控制.png`）。
  static const int batteryPercent = 78;

  /// 今日计划卡（`割草机-控制.png`）。
  static const String todayDate = '2026.08.31 · 周一';
  static const String todayRange = '09:00  →  12:30';
  static const String todayTaskLabel = '修边';
  static const String todayNext = '下一任务 16:00 - 20:00';

  static const String safetyTip = '开始割草前，请清理草坪中的障碍物';

  /// 周计划页顶上的合计（`割草机-割草计划.png`）。
  static const String weeklyTotal = '总工作时间：5小时23分钟';

  static const String timeZone = '(UTC+08:00) 北京、重庆、香港';
  static const String language = '简体中文';
}

/// 首页那张状态卡的四种态，对应设计稿的四张图。
///
/// 差别只有三处：电量环的两种颜色、环下面那行字、以及有没有充电光晕。其余（整机图、
/// 状态胶囊、安全提醒、今日计划、操作面板）四张图逐像素一致，所以页面只写一遍。
enum MowerPowerState {
  /// `割草机-控制.png`
  idle,

  /// `割草机-控制-充电中.png`
  charging,

  /// `割草机-控制-电量告警.png`
  batteryWarning,

  /// `割草机-控制-低电量.png`
  batteryLow;

  /// 环的进度色。
  Color get ringColor => switch (this) {
    idle || charging => MowerColors.brand,
    batteryWarning => MowerColors.warnRing,
    batteryLow => MowerColors.lowRing,
  };

  /// 环的底色（未走完的那段）。
  Color get ringTrackColor => switch (this) {
    idle || charging => MowerColors.ringTrack,
    batteryWarning => MowerColors.warnRingTrack,
    batteryLow => MowerColors.lowRingTrack,
  };

  int get percent => switch (this) {
    idle || charging => MowerDemoDevice.batteryPercent,
    batteryWarning => 30,
    batteryLow => 10,
  };

  /// 环下面那行字的前半段；[idle] 没有前半段（它只写「电量 78%」）。
  String? get statusLabel => switch (this) {
    idle => null,
    charging => '充电中',
    batteryWarning => '电量告警',
    batteryLow => '低电量',
  };

  Color get statusColor => switch (this) {
    idle || charging => MowerColors.brand,
    batteryWarning => MowerColors.warnText,
    batteryLow => MowerColors.lowText,
  };

  /// 那行字左边的小图标；[idle] 没有图标。
  String? get statusIcon => switch (this) {
    idle => null,
    charging => MowerAssets.batteryChargingIcon,
    batteryWarning => MowerAssets.batteryWarningIcon,
    batteryLow => MowerAssets.batteryLowIcon,
  };

  /// 充电态在图标背后多一圈光晕（`充电动效 / 光晕`）。
  bool get showChargingHalo => this == MowerPowerState.charging;

  /// 排查用：四个态在页面上轮着看。见 `MowerControlPage`。
  MowerPowerState get next =>
      MowerPowerState.values[(index + 1) % MowerPowerState.values.length];
}

/// 首页操作面板上的四颗按钮（`割草机操作面板 / 四按钮 / v2`）。
enum MowerAction {
  auto('自动', MowerAssets.actionAutoIcon),
  spot('定点', MowerAssets.actionSpotIcon),
  returnHome('回归', MowerAssets.actionReturnIcon),
  stop('停止', MowerAssets.actionStopIcon);

  const MowerAction(this.label, this.icon);

  final String label;
  final String icon;
}

/// 割草计划里的一个时段。
///
/// [day] 按稿子的列序来：0 = 周日，6 = 周六。[startMinutes] / [endMinutes] 是
/// 当天零点起的分钟数——图上那些块的高度就是按它算的，写成 "09:00" 反而要解析两次。
class MowerPlanSlot {
  const MowerPlanSlot({
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    required this.slot,
    this.trim = false,
  });

  final int day;
  final int startMinutes;
  final int endMinutes;

  /// 1 = 时段一，2 = 时段二。图例上那两个颜色就是它。
  final int slot;

  /// 修边时段：块上多一圈 `#97DCB6` 的描边（图例里的第三项）。
  final bool trim;

  String get startLabel => formatMinutes(startMinutes);
  String get endLabel => formatMinutes(endMinutes);

  Color get color => slot == 1 ? MowerColors.slotOne : MowerColors.slotTwo;

  static String formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// 周计划页的静态数据（`割草机-割草计划.png` 上画着的就是这四块）。
abstract final class MowerDemoPlan {
  /// 勾选了的那几天：日、二、四。
  static const List<bool> enabledDays = <bool>[
    true,
    false,
    true,
    false,
    true,
    false,
    false,
  ];

  static const List<String> dayLabels = <String>['日', '一', '二', '三', '四', '五', '六'];

  static const List<MowerPlanSlot> slots = <MowerPlanSlot>[
    MowerPlanSlot(day: 0, startMinutes: 480, endMinutes: 540, slot: 1),
    MowerPlanSlot(
      day: 0,
      startMinutes: 840,
      endMinutes: 900,
      slot: 2,
      trim: true,
    ),
    MowerPlanSlot(day: 2, startMinutes: 600, endMinutes: 720, slot: 1),
    MowerPlanSlot(
      day: 4,
      startMinutes: 900,
      endMinutes: 983,
      slot: 1,
      trim: true,
    ),
  ];

  /// 左边那列刻度。稿子上的时间轴不是匀的：08–18 拉开、两头压扁，
  /// 所以刻度也不是等距的，[MowerPlanChart] 用同一套锚点画块。
  static const List<int> axisHours = <int>[0, 8, 10, 12, 14, 16, 18, 24];
}

/// 消息通知页的一条（`割草机-消息通知.png`）。
class MowerMessage {
  const MowerMessage({
    required this.title,
    required this.time,
    required this.detail,
  });

  final String title;
  final String time;
  final String detail;
}

abstract final class MowerDemoMessages {
  static const List<String> tabs = <String>['日志', '提醒', '告警'];
  static const String dateFilter = '2026年8月31日';

  static const List<MowerMessage> items = <MowerMessage>[
    MowerMessage(
      title: '割草任务已完成',
      time: '10:42',
      detail: '区域 1 已按计划完成割草',
    ),
    MowerMessage(
      title: '设备电量较低',
      time: '08:15',
      detail: '当前电量 18%，建议及时充电',
    ),
    MowerMessage(
      title: '计划已调整',
      time: '昨天 18:30',
      detail: '周四时段 2 已更新为修边任务',
    ),
    MowerMessage(
      title: '设备重新上线',
      time: '8月30日 09:12',
      detail: 'Wi-Fi 连接已恢复',
    ),
  ];
}

/// 区域设置页的一行（`割草机-区域设置.png`）。
class MowerZone {
  const MowerZone({
    required this.name,
    required this.percent,
    required this.meters,
  });

  final String name;
  final int percent;
  final int meters;
}

abstract final class MowerDemoZones {
  static const List<MowerZone> zones = <MowerZone>[
    MowerZone(name: '区域 1', percent: 10, meters: 30),
    MowerZone(name: '区域 2', percent: 15, meters: 50),
    MowerZone(name: '区域 3', percent: 20, meters: 80),
    MowerZone(name: '区域 4', percent: 25, meters: 120),
    MowerZone(name: '区域 5', percent: 30, meters: 60),
  ];

  static const List<String> notes = <String>[
    '1. 区域设置总和不能大于 100%',
    '2. 距离最大可设置 200 米',
  ];

  /// 稿子上写的上限，滑块和距离都按它钳。
  static const int maxMeters = 200;
}

abstract final class MowerDemoTimeZones {
  static const List<String> options = <String>[
    '(UTC+12:00) 奥克兰、惠灵顿',
    '(UTC+09:00) 东京、首尔',
    '(UTC+08:00) 北京、重庆、香港',
    '(UTC+01:00) 巴黎、柏林',
    '(UTC+00:00) 伦敦、里斯本',
    '(UTC-05:00) 纽约、多伦多',
  ];
}

abstract final class MowerDemoLanguages {
  static const List<String> options = <String>['简体中文', 'English', '繁體中文'];
}

/// 割草机那套图里用到的、[AppColors] 里没有的颜色。
///
/// ⚠️ 不要顺手把它们搬进 [AppColors]：那份是花盆的语义色板，割草机这套是另一个
/// 产品的取色（连正文色都差了一档：#2A2B2B vs #252525）。混进去之后花盆页面改
/// 主色会把割草机也带歪。
abstract final class MowerColors {
  static const Color brand = AppColors.brandPrimary;

  /// 稿子上割草机页面的正文色，比花盆的 #252525 浅一点。
  static const Color ink = Color(0xFF2A2B2B);
  static const Color inkSecondary = Color(0x992A2B2B);
  static const Color inkTertiary = Color(0x662A2B2B);

  static const Color pageTop = Color(0xFFF8FAFB);

  /// 卡片：半透明白 + 一层很淡的品牌色投影。
  static const Color cardFill = Color(0xD1FFFFFF);
  static const Color navFill = Color(0xC7FFFFFF);
  static const Color chipFill = Color(0xFFEEF8F7);
  static const Color softFill = Color(0xFFEEF6F7);
  static const Color divider = Color(0xFFE3E8E8);

  static const Color ringTrack = Color(0xFFBFE5E3);
  static const Color warnRing = Color(0xFFF0AD33);
  static const Color warnRingTrack = Color(0xFFF2EDDB);
  static const Color warnText = Color(0xFFBA7A0F);
  static const Color lowRing = Color(0xFFE04F4F);
  static const Color lowRingTrack = Color(0xFFF5E8E8);
  static const Color lowText = Color(0xFFC43D3D);

  static const Color noticeFill = Color(0xFFFFF6DB);
  static const Color noticeBorder = Color(0x4DF2AD29);
  static const Color noticeText = Color(0xFF945C0A);

  static const Color slotOne = Color(0xFF70AFB5);
  static const Color slotTwo = Color(0xFF70B59C);
  static const Color trimBorder = Color(0xFF97DCB6);

  static const Color danger = Color(0xFFEB7275);
  static const Color dangerBorder = Color(0x8CEB7275);

  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x2170AFB5),
      blurRadius: 18,
      offset: Offset(0, 4),
    ),
  ];
}

/// 割草机页面用到的图，全部来自设计稿导出（`docs/UI/v2/割草机/`）。
abstract final class MowerAssets {
  static const String device = 'assets/images/mower_device.png';

  /// 设备列表 / 搜索列表里那颗 50×50 的圆角方图标（`设备图标 / 割草机`）。
  static const String listIcon = 'assets/images/mower_list_icon.png';

  static const String navHomeIcon = 'assets/images/mower_nav_home_icon.png';
  static const String navPlanIcon = 'assets/images/mower_nav_plan_icon.png';
  static const String navSettingsIcon =
      'assets/images/mower_nav_settings_icon.png';

  static const String actionAutoIcon =
      'assets/images/mower_action_auto_icon.png';
  static const String actionSpotIcon =
      'assets/images/mower_action_spot_icon.png';
  static const String actionReturnIcon =
      'assets/images/mower_action_return_icon.png';
  static const String actionStopIcon =
      'assets/images/mower_action_stop_icon.png';

  /// 「继续」那颗：稿子上是停止的同位替换态（`操作 / 继续`）。
  static const String actionResumeIcon =
      'assets/images/mower_action_resume_icon.png';

  static const String safetyTipIcon = 'assets/images/mower_safety_tip_icon.png';
  static const String wifiIcon = 'assets/images/mower_wifi_icon.png';
  static const String bluetoothIcon = 'assets/images/mower_bluetooth_icon.png';

  static const String batteryChargingIcon =
      'assets/images/mower_battery_charging_icon.png';
  static const String batteryWarningIcon =
      'assets/images/mower_battery_warning_icon.png';
  static const String batteryLowIcon =
      'assets/images/mower_battery_low_icon.png';
}
