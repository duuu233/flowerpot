import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// 割草机页面的**界面常量**：状态卡四种视觉态、计划表坐标轴、配色、图片。
///
/// ⚠️ 2026-09-23 开始真机联调，这个文件（原 `mower_ui.dart`）里的**假数据全部删掉**：
/// 搜索页 / 设备列表那条写死的割草机（`MowerDemo`）、稿子上的名称/型号/SN/电量
/// （`MowerDemoDevice`）、稿子上那四块计划（`MowerDemoPlan.slots`）、消息通知那四条
/// （`MowerDemoMessages`）。页面上的数一律来自设备（DP / DeviceBean）或涂鸦接口，
/// 没有就空着，不再编。

/// 首页那张状态卡的四种**视觉**态，对应设计稿的四张图。
///
/// ⚠️ 2026-09-18 接 DP 之后它只管**长相**，不再自带数字：电量来自 DP13、
/// 是不是充电中来自 DP117，由 `MowerControlPage._tone` 换算成这里的四个值之一。
enum MowerPowerState {
  /// `割草机-控制.png`
  idle,

  /// `割草机-控制-充电中.png`（DP117=charging/full）
  charging,

  /// `割草机-控制-电量告警.png`（电量 ≤ [warningPercent]）
  batteryWarning,

  /// `割草机-控制-低电量.png`（电量 ≤ [lowPercent]）
  batteryLow;

  /// 🔶 这两条阈值**协议里没有**（DP13 只是 0-100 的电量），是端上为了把稿子那两张
  /// 图用起来定的。产品另有口径就改这两个数。
  static const int warningPercent = 30;
  static const int lowPercent = 10;

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
}

// ⚠️ 原来这里有个 `MowerAction` 枚举（自动/定点/回归/停止）。2026-09-18 接 DP 之后
// 左边三颗直接用 DP3 的 `MowerMode`（smart/spot/goto_charge），最右那颗是 DP2 的开关，
// 图标与文案在 `MowerControlPage._ActionPanel` 里就地对应，不再单独维护一份枚举。

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

/// 周计划表的坐标轴（界面常量，不是数据）。
abstract final class MowerPlanAxis {
  static const List<String> dayLabels = <String>['日', '一', '二', '三', '四', '五', '六'];

  /// 左边那列刻度。稿子上的时间轴不是匀的：08–18 拉开、两头压扁，
  /// 所以刻度也不是等距的，[MowerPlanChart] 用同一套锚点画块。
  static const List<int> axisHours = <int>[0, 8, 10, 12, 14, 16, 18, 24];
}

// ⚠️ 区域（`MowerZone` / `MowerDemoZones`）、时区（`MowerDemoTimeZones`）、
// 语言（`MowerDemoLanguages`）三块静态数据 2026-09-18 接 DP 之后**已删**：
// 它们现在由功能点表给——分别是 `MowerZoneConfig`（DP103）、`MowerTimezone`（DP107 的
// 25 个枚举）、`MowerLanguage`（DP109 的 18 个枚举），见 `mower_dp.dart`。
// 稿子上那几个中文时区/语言名留在 `MowerTimezone._cities` 与 `MowerLanguage.label` 里。

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

  /// 设备列表卡片里那张整机俯视图（`设备卡片 / YSmower-01`）。
  ///
  /// ⚠️ 稿子里这张是把导出的横图**逆时针转 90°**摆的（车头朝上），导出件本身是横的；
  /// 已经转好再入库，页面不要再转一次。
  static const String deviceThumb = 'assets/images/mower_device_thumb.png';

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
