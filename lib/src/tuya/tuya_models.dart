import 'package:flutter/material.dart';

enum LoginRegion { domestic, overseas }

enum SensorMetric {
  waterLevel,
  soilMoisture,
  light,
  ppfd,
  dli,
  temperature,
  humidity,
  battery,
}

enum ReportRange { day, week, month }

/// Health readings the planter classifies itself, rather than the app deriving
/// them from a threshold.
///
/// Every field is nullable: a freshly bound device has not reported the DP yet,
/// and the status pages fall back to their own thresholds until it does.
enum BatteryStatus { shortage, good, charging }

enum WaterNeedsStatus { shortage, drinking, watery }

enum LightingCondition { shortage, good, veryGood }

/// Shared by `air_temperature_status` (cold/suitable/heat) and
/// `air_humidity_status` (dry/suitable/damp), which differ only in wording.
enum ComfortLevel { low, suitable, high }

/// DP 162 `plant_confirm`：设备告诉 App 要不要弹引导窗。
///
/// 两态，且**只上报、App 不下发**：设备识别到新植物时报"要弹"，App 下发植物 DPID 之后
/// 固件自己改回"不弹"并立即上报；植物 DPID 为 -1（没插植物）或用户关掉自动检测时，
/// 固件同样报"不弹"。
///
/// ## 2026-09-11：DP 类型由数值改成布尔
///
/// 产品口径：`pdid162=0` → `false`（不弹），`pdid162=1` → `true`（弹）。也就是这一项在
/// 涂鸦后台已从 value 型改成 **bool 型**，桥接收到的是 Dart `bool` 而不是数字。
///
/// [fromDp] 同时认布尔和旧的数值/字符串：真机上两种固件可能并存（没升级的还在报 0/1），
/// 只认一种会让其中一批设备永远不弹窗。新老两套都映射到同一个结论。
enum PlantConfirmState {
  /// `false` / `0`：不弹窗。
  hidden(false),

  /// `true` / `1`：弹引导窗，让用户确认盆里这一株。
  prompt(true);

  const PlantConfirmState(this.dpValue);

  /// 上报用的值。2026-09-11 起是布尔（此前是 0 / 1）。
  final bool dpValue;

  /// 解析设备上报的 DP 162。
  ///
  /// 认三种形态，按可能性排序：
  ///
  /// 1. **`bool`** —— 2026-09-11 起的口径，`true` 弹、`false` 不弹；
  /// 2. **数值** —— 旧固件的 `1` / `0`；
  /// 3. **字符串** —— 某些桥接路径会把 DP 值字符串化（`'true'` / `'1'`）。
  ///
  /// 其余一切（没上报过、`null`、认不出的值）都按**不弹**处理：宁可少弹一次，也不要让
  /// 老固件的设备每次进详情页都被问一遍。
  static PlantConfirmState fromDp(Object? raw) {
    if (raw is bool) return raw ? prompt : hidden;
    if (raw is num) return raw.toInt() == 1 ? prompt : hidden;
    final text = '${raw ?? ''}'.trim().toLowerCase();
    if (text == 'true' || text == '1') return prompt;
    return hidden;
  }
}

/// DP 116 `plant_variety` 的取值。
///
/// 2026-09-09 起是数字：**-1 表示盆里没有植物**，0..N 是具体植物，数值等于管理
/// 后台植物管理里的「涂鸦标识 ID」（0 是通用植物）。老固件报的是字符串标识符，
/// 解析不出数字时返回 null，调用方退回按字符串匹配。
abstract final class PlantVariety {
  /// 没有植物的约定值。
  static const int none = -1;

  /// 通用植物：固件识别不出具体品种时报这个。后台不再为它建植物数据，所以 App
  /// 拿它匹配不到目录项，引导窗要走「请选择并确认植物」那一支。
  static const int generic = 0;

  static int? parse(Object? raw) {
    if (raw is num) return raw.toInt();
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  /// 盆里确实有一株植物：解析得出数字且不是 -1。字符串标识符（老固件）也算有。
  static bool hasPlant(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return false;
    final value = parse(raw);
    return value == null || value >= 0;
  }

  /// 设备明确报了「没有植物」。
  static bool isMissing(Object? raw) => parse(raw) == none;
}

class DeviceStatusReport {
  const DeviceStatusReport({
    this.battery,
    this.waterNeeds,
    this.lighting,
    this.temperature,
    this.humidity,
  });

  final BatteryStatus? battery;
  final WaterNeedsStatus? waterNeeds;
  final LightingCondition? lighting;
  final ComfortLevel? temperature;
  final ComfortLevel? humidity;
}

/// Sensor history the device reports as raw DPs, already decoded into one
/// series per metric and range.
class DeviceHistory {
  const DeviceHistory(this._series);

  static const empty = DeviceHistory(<String, List<double>>{});

  final Map<String, List<double>> _series;

  static String key(SensorMetric metric, ReportRange range) =>
      '${metric.name}.${range.name}';

  /// Empty when the product has no history DP for [metric], or when the device
  /// has not reported that window yet.
  List<double> series(SensorMetric metric, ReportRange range) =>
      _series[key(metric, range)] ?? const <double>[];

  bool has(SensorMetric metric, ReportRange range) =>
      (_series[key(metric, range)] ?? const <double>[]).isNotEmpty;
}

/// A change the planter pushed on its own, rather than an answer to a call the
/// app made.
///
/// The device reports DP 103–115 and the nine history packets whenever it has
/// something new; the app only ever asks for the full list at login and on a
/// pull-to-refresh, so without this every reading on screen would be as old as
/// the last list load.
class DeviceUpdate {
  /// The device as it now stands, with the reported DPs already merged into
  /// the last known snapshot.
  const DeviceUpdate.changed(
    SmartPlanterDevice this.device, {
    this.changedDps = const <int>{},
  }) : removedId = null;

  /// The device left the account — unbound from another phone, or reset.
  const DeviceUpdate.removed(String this.removedId)
    : device = null,
      changedDps = const <int>{};

  final SmartPlanterDevice? device;
  final String? removedId;

  /// **这一条上报里真正带了哪几个 DP**，不是设备当前的全部 DP。
  ///
  /// 设备快照是「历史 DP 合并后的样子」，所以光看 [device] 分不出「162 这次报了
  /// true」和「162 上次报过 true、这次报的是温度」。植物确认弹窗要的就是前者
  /// （2026-09-12 产品：「再次接收到 DP162 true 的时候……就需要再次弹框」），
  /// 所以把本次报文的 DP 号原样带上来。
  ///
  /// 桥接没给 `dps` 时（例如只有在线状态变化）是空集合。
  final Set<int> changedDps;
}

/// 固件升级的实时状态。
///
/// 涂鸦的 OTA 是个长过程：`startOta` 只是把升级发起出去，设备下载加烧录要几
/// 分钟，期间 SDK 通过监听器回报进度。所以"升级完成"只能由 [success] 事件
/// 断定，不能在发起调用返回时就宣布。
class OtaProgress {
  const OtaProgress({
    required this.deviceId,
    required this.status,
    this.percent,
    this.message,
    this.stage,
  });

  final String deviceId;
  final OtaStatus status;

  /// 0–100，仅 [OtaStatus.running] 时有值。
  final int? percent;

  /// 失败原因，仅 [OtaStatus.failed] 时有值。
  final String? message;

  /// 原生报上来的升级阶段（涂鸦状态码换算），没报时为 null。见 [OtaStage.fromTuya]。
  final OtaStage? stage;

  /// 进度到这个百分比就当设备已经在装了，界面改说「固件安装中」（2026-09-17 产品）。
  ///
  /// 涂鸦的进度到 98% 之后会**停在那儿等设备写完固件再重启**，这一段是整条升级里
  /// 最长的一截，停在「固件升级中 98%」看着就像卡死了。98% 往后那两格并没有可信的
  /// 进度可言，所以干脆并进安装中：进度条换成来回走的动画、不写数字（和「固件准备中」
  /// 同一套动效），等涂鸦报成功再走原来的「升级完成」。
  static const installingPercent = 98;

  /// 进行中时界面该说哪一句（2026-09-15 产品：一直停在「0%」像是卡住了，要动态换文案）。
  ///
  /// 以进度为主、涂鸦阶段为辅：
  /// - 还没有进度（0%）→ 准备中；涂鸦报「等待设备唤醒」时说等待唤醒；
  /// - 有进度（1–97%）→ 升级中；
  /// - 进度到 [installingPercent] 但还没收到成功，或涂鸦报「固件已下载到设备」
  ///   → 安装中（设备在写入、重启）。
  OtaStage get displayStage {
    if (stage == OtaStage.installing) return OtaStage.installing;
    final value = percent ?? 0;
    if (value >= installingPercent) return OtaStage.installing;
    if (value > 0) return OtaStage.upgrading;
    return stage == OtaStage.waitingWake
        ? OtaStage.waitingWake
        : OtaStage.preparing;
  }
}

enum OtaStatus { running, success, failed }

/// 升级进行中的阶段。
///
/// 涂鸦（SDK 7.5.1 `DevUpgradeStatusEnum` 解包 + 官方文档）的进行中状态码：13 云端排队、
/// 14 云端准备、100 App 准备、2 升级中、5 等待设备唤醒、6 固件已下载到设备。**没有**
/// 独立的「下载中 / 传输中 / 安装中」，所以这里只分四段，文案由 [OtaProgress.displayStage]
/// 按进度推出来。
enum OtaStage {
  preparing,
  upgrading,
  installing,
  waitingWake;

  static OtaStage? fromTuya(Object? raw) {
    final value = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    return switch (value) {
      13 || 14 || 100 => OtaStage.preparing,
      2 => OtaStage.upgrading,
      5 => OtaStage.waitingWake,
      6 => OtaStage.installing,
      _ => null,
    };
  }
}

/// 一个被分享到的接收方。
///
/// 涂鸦文档里的设备分享是按账号进行的：把设备分享给某个手机号/邮箱，接收方在
/// 自己的账号里看到这台设备。链接分享只有 Android 业务拓展 SDK 才有，iOS 的
/// Home SDK 没有对应接口，所以两端统一走账号。
class DeviceShareMember {
  const DeviceShareMember({
    required this.memberId,
    required this.name,
    this.account,
  });

  /// 取消分享时要回传给 SDK 的成员 id。
  final String memberId;

  /// 接收方昵称，SDK 没给时回落到账号。
  final String name;

  /// 手机号或邮箱，SDK 未必返回。
  final String? account;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.nickname,
    required this.account,
    this.avatarUrl,
  });

  final String id;
  final String nickname;
  final String account;
  final String? avatarUrl;

  AppUser copyWith({String? nickname, String? avatarUrl}) => AppUser(
    id: id,
    nickname: nickname ?? this.nickname,
    account: account,
    avatarUrl: avatarUrl ?? this.avatarUrl,
  );
}

class PlantProfile {
  /// No catalog response yet; never substitute another plant's data.
  static const unavailable = PlantProfile(
    id: '', name: '植物资料暂未获取', latinName: '',
    color: Color(0xFF4D8B55), moistureTarget: 0, lightTarget: 0, tip: '',
  );

  const PlantProfile({
    required this.id,
    required this.name,
    required this.latinName,
    required this.color,
    required this.moistureTarget,
    required this.lightTarget,
    required this.tip,
    this.productPlantId,
    this.userProductPlantId,
    this.tuyaIdentifier = '',
    this.imageUrl,
    this.alias = '',
    this.introduction = '',
    this.temperatureRequirement = '',
    this.humidityRequirement = '',
    this.lightingRequirement = '',
    this.wateringFrequency = '',
    this.growthCharacteristics = '',
    this.careInstructions = '',
    this.lightingSuggestion = '',
    this.waterSuggestion = '',
    this.temperatureSuggestion = '',
    this.humiditySuggestion = '',
    this.difficultyMaintenance,
    this.plantType,
  });

  final String id;
  final String name;
  final String latinName;
  final Color color;
  final int moistureTarget;
  final int lightTarget;
  final String tip;

  /// Backend ids used by the plant APIs; absent while details are unavailable.
  final int? productPlantId;
  final int? userProductPlantId;

  /// Value written to and reported by `plant_variety` (DP 116).
  ///
  /// The backend field is named `tuYaRemark`; it is intentionally kept
  /// separate from the numeric database id.
  final String tuyaIdentifier;
  final String? imageUrl;

  /// Optional detail fields returned by the backend plant-detail endpoints.
  final String alias;
  final String introduction;
  final String temperatureRequirement;
  final String humidityRequirement;
  final String lightingRequirement;
  final String wateringFrequency;
  final String growthCharacteristics;
  final String careInstructions;

  /// 后台「植物资料」里单独维护的四条建议文案（`lightingSuggestions` /
  /// `waterSuggestion` / `temperatureSuggestion` / `humiditySuggestion`）。
  ///
  /// 与上面的 *Requirement 不是一回事：那几个是阈值区间（如 `18-29℃`），
  /// 这四条是给用户看的建议。后台没配就是空串，页面不显示对应行，不编造。
  final String lightingSuggestion;
  final String waterSuggestion;
  final String temperatureSuggestion;
  final String humiditySuggestion;

  final int? difficultyMaintenance;

  /// 后台配的植物分类，下发进 `plant_type` (161) 的枚举 `1`/`2`/`3`。
  ///
  /// 后台没配（或配了范围外的值）时为 null，绑定植物时就只下发 116。分类是设备
  /// 侧的养护策略输入，猜一个填进去比缺一个更糟。
  final int? plantType;

  PlantProfile copyWith({
    int? userProductPlantId,
    bool clearUserProductPlantId = false,
  }) => PlantProfile(
    id: id,
    name: name,
    latinName: latinName,
    color: color,
    moistureTarget: moistureTarget,
    lightTarget: lightTarget,
    tip: tip,
    productPlantId: productPlantId,
    userProductPlantId: clearUserProductPlantId
        ? null
        : userProductPlantId ?? this.userProductPlantId,
    tuyaIdentifier: tuyaIdentifier,
    imageUrl: imageUrl,
    alias: alias,
    introduction: introduction,
    temperatureRequirement: temperatureRequirement,
    humidityRequirement: humidityRequirement,
    lightingRequirement: lightingRequirement,
    wateringFrequency: wateringFrequency,
    growthCharacteristics: growthCharacteristics,
    careInstructions: careInstructions,
    lightingSuggestion: lightingSuggestion,
    waterSuggestion: waterSuggestion,
    temperatureSuggestion: temperatureSuggestion,
    humiditySuggestion: humiditySuggestion,
    difficultyMaintenance: difficultyMaintenance,
    plantType: plantType,
  );
}

class SensorSnapshot {
  const SensorSnapshot({
    required this.waterLevel,
    required this.soilMoisture,
    required this.illuminance,
    required this.ppfd,
    required this.airTemperature,
    required this.relativeHumidity,
    this.par = 0,
  });

  final int waterLevel;
  final int soilMoisture;
  final int illuminance;

  /// Photosynthetic photon flux density in μmol/m²/s.
  ///
  /// `light_ppfd_value` is a whole number on the wire, but the mock backend and
  /// the DLI derivation both work in fractions, so this stays a double all the
  /// way through the presentation layer.
  final double ppfd;

  /// Photosynthetically active radiation in μmol/m², from
  /// `light_par_value`. Reported but not on any screen yet.
  final double par;
  final double airTemperature;
  final int relativeHumidity;

  double valueFor(SensorMetric metric) => switch (metric) {
    SensorMetric.waterLevel => waterLevel.toDouble(),
    SensorMetric.soilMoisture => soilMoisture.toDouble(),
    SensorMetric.light => illuminance.toDouble(),
    SensorMetric.ppfd => ppfd,
    SensorMetric.dli => ppfd * 0.0432,
    SensorMetric.temperature => airTemperature,
    SensorMetric.humidity => relativeHumidity.toDouble(),
    SensorMetric.battery => 0,
  };
}

class DeviceControlSettings {
  const DeviceControlSettings({
    this.autoBrightness = true,
    this.soundInteraction = true,
    this.soundSensitivity = 62,
    this.touchInteraction = true,
    this.touchSensitivity = 70,
    this.vibration = true,
    this.touchKeyVibration = true,
    this.touchPlantVibration = true,
    this.napEnabled = true,
    this.napPeriod = '12:30-13:30',
    this.nightEnabled = true,
    this.nightPeriod = '23:00-07:00',
    this.temperatureUnit = 'celsius',
    this.clockFormat = '24h',
    this.standbyEnabled = false,
    this.standbyDelayMinutes = 30,
    this.deviceLanguage = 'zh',
    this.plantDetection = true,
  });

  final bool autoBrightness;
  final bool soundInteraction;
  final int soundSensitivity;
  final bool touchInteraction;
  final int touchSensitivity;
  final bool vibration;

  /// `touch_vib_switch` and `touch_plant_vib_switch`: the device splits haptics
  /// into the key press and the plant touch. Read and writable, but the
  /// vibration page only draws the master switch so far.
  final bool touchKeyVibration;
  final bool touchPlantVibration;
  final bool napEnabled;

  /// `HH:MM-HH:MM`. The device carries each end as its own minutes-past-
  /// midnight DP; the pair is joined here because every screen edits them
  /// together.
  final String napPeriod;
  final bool nightEnabled;
  final String nightPeriod;
  final String temperatureUnit;
  final String clockFormat;

  /// `standby_switch` (151). The export's default is 0 — never enter standby —
  /// so an unreported device must not be drawn as "standby on".
  final bool standbyEnabled;

  /// `standby_delay` (152), whole minutes, 1–180.
  final int standbyDelayMinutes;

  /// `language` (153), as the app's own `zh`/`en` code rather than the DP's
  /// `Chinese`/`English`. Factory reset returns the device to Chinese.
  final String deviceLanguage;

  /// `plant_detect_switch`：自动检测植物的总开关。关掉之后设备不再比对盆里的
  /// 植物，`plant_confirm`(162) 固定报 0，App 也就不会再弹引导窗。
  ///
  /// 未上报时按开启处理：这是设备的默认行为，按关闭画会让开关和实际状态相反。
  final bool plantDetection;

  /// Whether the device is currently set to Fahrenheit (`temp_unit_convert`).
  bool get usesFahrenheit => temperatureUnit == 'fahrenheit';

  String get temperatureSymbol => usesFahrenheit ? '°F' : '°C';

  /// The device reports `air_temperature` in whatever unit
  /// `temp_unit_convert` selects — the platform export gives DP 112's unit as
  /// `°C/°F` — so a reading is never converted here, only labelled. What does
  /// need converting is the app's own Celsius numbers: comfort thresholds,
  /// advice ranges and chart bounds.
  double temperatureFromCelsius(double celsius) =>
      usesFahrenheit ? celsius * 9 / 5 + 32 : celsius;

  /// A reading as the device reports it, with the unit it is in.
  String formatTemperature(double value, {int fractionDigits = 1}) =>
      '${value.toStringAsFixed(fractionDigits)}$temperatureSymbol';

  /// A Celsius range from the app's own copy, in the device's unit.
  String formatCelsiusRange(
    double low,
    double high, {
    int fractionDigits = 0,
  }) =>
      '${temperatureFromCelsius(low).toStringAsFixed(fractionDigits)}'
      '$temperatureSymbol~'
      '${temperatureFromCelsius(high).toStringAsFixed(fractionDigits)}'
      '$temperatureSymbol';

  /// Whether the device is set to a 12-hour clock (`time_format`).
  bool get uses12HourClock => clockFormat == '12h';

  /// An `HH:MM` label in the clock format the device is set to. Anything that
  /// does not parse is returned unchanged, so a label that is already
  /// formatted — or a placeholder — passes through.
  String formatClock(String label) {
    if (!uses12HourClock) return label;
    final parts = label.split(':');
    if (parts.length != 2) return label;
    final hour = int.tryParse(parts.first);
    final minute = int.tryParse(parts.last);
    if (hour == null || minute == null) return label;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return label;
    final meridiem = hour < 12 ? '上午' : '下午';
    final twelve = hour % 12 == 0 ? 12 : hour % 12;
    return '$meridiem $twelve:${minute.toString().padLeft(2, '0')}';
  }

  /// An `HH:MM-HH:MM` period in the device's clock format.
  String formatPeriod(String period) {
    final parts = period.split('-');
    if (parts.length != 2) return period;
    return '${formatClock(parts.first)}-${formatClock(parts.last)}';
  }

  DeviceControlSettings copyWith({
    bool? autoBrightness,
    bool? soundInteraction,
    int? soundSensitivity,
    bool? touchInteraction,
    int? touchSensitivity,
    bool? vibration,
    bool? touchKeyVibration,
    bool? touchPlantVibration,
    bool? napEnabled,
    String? napPeriod,
    bool? nightEnabled,
    String? nightPeriod,
    String? temperatureUnit,
    String? clockFormat,
    bool? standbyEnabled,
    int? standbyDelayMinutes,
    String? deviceLanguage,
    bool? plantDetection,
  }) => DeviceControlSettings(
    autoBrightness: autoBrightness ?? this.autoBrightness,
    soundInteraction: soundInteraction ?? this.soundInteraction,
    soundSensitivity: soundSensitivity ?? this.soundSensitivity,
    touchInteraction: touchInteraction ?? this.touchInteraction,
    touchSensitivity: touchSensitivity ?? this.touchSensitivity,
    vibration: vibration ?? this.vibration,
    touchKeyVibration: touchKeyVibration ?? this.touchKeyVibration,
    touchPlantVibration: touchPlantVibration ?? this.touchPlantVibration,
    napEnabled: napEnabled ?? this.napEnabled,
    napPeriod: napPeriod ?? this.napPeriod,
    nightEnabled: nightEnabled ?? this.nightEnabled,
    nightPeriod: nightPeriod ?? this.nightPeriod,
    temperatureUnit: temperatureUnit ?? this.temperatureUnit,
    clockFormat: clockFormat ?? this.clockFormat,
    standbyEnabled: standbyEnabled ?? this.standbyEnabled,
    standbyDelayMinutes: standbyDelayMinutes ?? this.standbyDelayMinutes,
    deviceLanguage: deviceLanguage ?? this.deviceLanguage,
    plantDetection: plantDetection ?? this.plantDetection,
  );
}

class SmartPlanterDevice {
  const SmartPlanterDevice({
    required this.id,
    required this.productId,
    required this.name,
    required this.online,
    this.iconUrl = '',
    required this.signal,
    required this.battery,
    required this.charging,
    required this.boundAt,
    required this.plant,
    required this.sensors,
    required this.settings,
    required this.firmwareVersion,
    required this.macAddress,
    this.hardwareVersion = '--',
    this.plantVariety = '',
    this.plantConfirm = PlantConfirmState.hidden,
    this.plantConfirmRaw = '',
    this.deviceStatus = '',
    this.reportedDays,
    this.status = const DeviceStatusReport(),
    this.history = DeviceHistory.empty,
    this.birthday,
    this.weddingDay,
    this.lastOperationResult = '',
  });

  final String id;
  final String productId;
  final String name;

  /// 涂鸦平台上给这个产品配的图（`DeviceBean.getIconUrl`）。
  ///
  /// 设备列表那一列画的就是它——那一页的数据全部来自涂鸦，和 APP 后端的植物图
  /// 是两回事（2026-09-12 产品口径）。没配就是空串，页面留空。
  final String iconUrl;
  final bool online;
  final int signal;
  final int battery;
  final bool charging;
  final DateTime boundAt;
  final PlantProfile plant;
  final SensorSnapshot sensors;
  final DeviceControlSettings settings;
  final String firmwareVersion;
  final String macAddress;

  /// `hardware_version`, reported as a plain number.
  final String hardwareVersion;

  /// `plant_variety`: the backend `tuYaRemark` identifier. DP 116 is both
  /// writable and reportable, so a device report can become the active [plant].
  ///
  /// 2026-09-09 起是植物 id：`-1` 表示盆里没有植物，`0..N` 是后台植物管理里的
  /// 「涂鸦标识 ID」。老固件报的字符串标识符仍能匹配（见 `FlowerpotState._plantKey`）。
  final String plantVariety;

  /// `plant_confirm` (162)：设备要不要 App 弹「发现新植物」引导窗，只上报、
  /// App 不下发。取值见 [PlantConfirmState]。
  final PlantConfirmState plantConfirm;

  /// DP 162 **上报上来的原始值**，原样保留，供联调核对用。
  ///
  /// [plantConfirm] 会把一切认不出的东西都归成 `hidden`，排查时就看不出设备到底报了
  /// 什么（没上报过？报了 0？报了别的？）。这里留一份原文：没上报过是空串。
  final String plantConfirmRaw;

  /// `device_status`, an opaque product-defined string.
  final String deviceStatus;

  /// `together_days`, pushed once a day at midnight. Null until the device has
  /// reported it, which is why [companionDays] still has a local fallback.
  final int? reportedDays;

  final DeviceStatusReport status;
  final DeviceHistory history;

  /// `memorial_birthday` (158) and `memorial_wedding` (159). Null means the
  /// device has never been given one, or it was disabled.
  final DateTime? birthday;
  final DateTime? weddingDay;

  /// `op_result` (160), the device's receipt for the last command it ran, as
  /// `<操作>:<对象>:<结果>`. Empty until it reports one.
  final String lastOperationResult;

  /// Whether the last receipt says the operation succeeded. Null when the
  /// device has reported nothing, or something this app cannot parse.
  bool? get lastOperationSucceeded {
    final parts = lastOperationResult.split(':');
    if (parts.length < 3) return null;
    return switch (parts.last.trim()) {
      'ok' => true,
      'fail' => false,
      _ => null,
    };
  }

  int get companionDays =>
      reportedDays ?? DateTime.now().difference(boundAt).inDays + 1;

  SmartPlanterDevice copyWith({
    String? name,
    String? iconUrl,
    bool? online,
    int? signal,
    int? battery,
    bool? charging,
    PlantProfile? plant,
    SensorSnapshot? sensors,
    DeviceControlSettings? settings,
    String? firmwareVersion,
    String? plantVariety,
    PlantConfirmState? plantConfirm,
    String? plantConfirmRaw,
    DeviceStatusReport? status,
    DeviceHistory? history,
    DateTime? birthday,
    bool clearBirthday = false,
    DateTime? weddingDay,
    bool clearWeddingDay = false,
    String? lastOperationResult,
  }) => SmartPlanterDevice(
    id: id,
    productId: productId,
    name: name ?? this.name,
    iconUrl: iconUrl ?? this.iconUrl,
    online: online ?? this.online,
    signal: signal ?? this.signal,
    battery: battery ?? this.battery,
    charging: charging ?? this.charging,
    boundAt: boundAt,
    plant: plant ?? this.plant,
    sensors: sensors ?? this.sensors,
    settings: settings ?? this.settings,
    firmwareVersion: firmwareVersion ?? this.firmwareVersion,
    macAddress: macAddress,
    hardwareVersion: hardwareVersion,
    plantVariety: plantVariety ?? this.plantVariety,
    plantConfirm: plantConfirm ?? this.plantConfirm,
    plantConfirmRaw: plantConfirmRaw ?? this.plantConfirmRaw,
    deviceStatus: deviceStatus,
    reportedDays: reportedDays,
    status: status ?? this.status,
    history: history ?? this.history,
    birthday: clearBirthday ? null : (birthday ?? this.birthday),
    weddingDay: clearWeddingDay ? null : (weddingDay ?? this.weddingDay),
    lastOperationResult: lastOperationResult ?? this.lastOperationResult,
  );
}

class AnimationAsset {
  const AnimationAsset({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    this.synced = false,
  });

  final String id;
  final String name;
  final String path;
  final DateTime createdAt;
  final bool synced;

  AnimationAsset copyWith({bool? synced}) => AnimationAsset(
    id: id,
    name: name,
    path: path,
    createdAt: createdAt,
    synced: synced ?? this.synced,
  );
}

/// 配网请求。
///
/// **没有模式字段了。** 以前带一个 `mode`（`ap` / `ez`），2026-09-11 删掉：EZ 真机实测
/// 设备不支持、整条路已经删干净，Android 原生侧也早就不读它（`2b0a4b8` 把
/// `if (requested == "ap")` 改成无条件）。留着一个只有一种取值的字段，唯一的作用是
/// 让人以为还能切——而万一漏传，iOS 那边会静默按另一种模式发，排查起来完全看不出。
class PairingRequest {
  const PairingRequest({required this.ssid, required this.password});

  final String ssid;
  final String password;
}

/// One access point seen by the phone.
class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.level,
    required this.frequency,
  });

  final String ssid;

  /// Signal strength in dBm, closer to 0 is stronger.
  final int level;

  /// Channel frequency in MHz. Tuya provisioning only works on 2.4 GHz.
  final int frequency;

  bool get is24g => frequency >= 2400 && frequency < 2500;

  /// Bars the pairing UI draws, 1 to 4. Cut points follow the usual Android
  /// `WifiManager.calculateSignalLevel` steps.
  int get signalBars => switch (level) {
    >= -55 => 4,
    >= -65 => 3,
    >= -75 => 2,
    _ => 1,
  };

  /// Access points a planter raises in AP provisioning mode.
  bool get looksLikeDeviceHotspot => isDeviceHotspotName(ssid);

  /// SSID prefix handed to the platform when no hotspot name is known, so the
  /// system picker lists the matching access points itself. Deliberately
  /// shorter than a full product name: it has to cover `SmartLife-…` and the
  /// `SmartLift-…` variant seen on shipped planters, and a prefix that matches
  /// nothing produces no picker at all — which on Android is indistinguishable
  /// from the user cancelling it.
  static const String hotspotJoinPrefix = 'SmartLi';

  /// Same test against a bare name, for the SSID the phone is currently on:
  /// that one arrives without a scan entry behind it.
  ///
  /// Separators differ between firmware builds (`SmartLife-8987`,
  /// `smart_life 8987`), so they are dropped before matching, and the
  /// `smartlife` prefix is cut one letter short: shipped planters have been
  /// seen raising `SmartLift-…`. This list stays a guess either way — what a
  /// name outside it must never do is hide the device, which is why the
  /// pairing pages can also list the raw scan through [WifiScan.otherNetworks].
  static bool isDeviceHotspotName(String ssid) {
    final name = ssid.trim().toLowerCase();
    if (name.isEmpty) return false;
    // `ty_`/`ty-` keeps its separator: a bare `ty` prefix would swallow
    // ordinary router names.
    if (name.startsWith('ty_') || name.startsWith('ty-')) return true;
    final compact = name.replaceAll(RegExp(r'[\s_\-]'), '');
    return compact.startsWith('smartlif') ||
        compact.startsWith('tuya') ||
        compact.startsWith('ysplanter');
  }
}

/// 这台手机 / 这个包能不能用 BLE 发现。
///
/// 三件事分开报而不是折成一个 bool：**手机没有 BLE 硬件**、**蓝牙开关关着**、
/// **包里根本没有蓝牙模块**，处置完全不同——第二种让用户开一下蓝牙就行，第一、三种
/// 只能回落到 Wi-Fi 扫描。糅成 false 就又变成让人猜（`PRODUCT_RULES` §4.1）。
class BleAvailability {
  const BleAvailability({
    required this.available,
    required this.supported,
    required this.enabled,
    this.locationOn = true,
    this.scanPermission = true,
    this.locationPermission = true,
    this.sdkInt = 0,
    this.release = '',
    this.reason = '',
  });

  factory BleAvailability.fromMap(Map<Object?, Object?> raw) => BleAvailability(
    available: raw['available'] == true,
    supported: raw['supported'] == true,
    enabled: raw['enabled'] == true,
    // 缺省按 true：老桥接不回这三项时，别凭空报一个「定位没开」把人带偏。
    sdkInt: (raw['sdkInt'] as num?)?.toInt() ?? 0,
    release: raw['release']?.toString() ?? '',
    locationOn: raw['locationOn'] != false,
    scanPermission: raw['scanPermission'] != false,
    locationPermission: raw['locationPermission'] != false,
    reason: raw['reason']?.toString() ?? '',
  );

  /// SDK 里有蓝牙模块、拿得到操作实例。false 表示这个包根本没这条路。
  final bool available;

  /// 这台手机有 BLE 硬件。
  final bool supported;

  /// 蓝牙开关开着。
  final bool enabled;

  /// **系统的「定位服务」开关**是否打开。
  ///
  /// ⚠️ 这是 BLE 扫描最容易被忽略的一道门：Android 6～11 强制要求它，而我们在 12+ 又
  /// 刻意没用 `neverForLocation`（那个标志会让系统把 iBeacon 类广播从结果里过滤掉），
  /// 所以同样受它影响。**关着的时候扫描静默返回空**——不报错、不回调，和「附近没有设备」
  /// 完全分不开。它不是权限、申请不来，只能检测出来让用户自己去开。
  final bool locationOn;

  /// Android 12+ 的「附近的设备」权限（`BLUETOOTH_SCAN`）。
  final bool scanPermission;

  /// 定位权限（`ACCESS_FINE_LOCATION`）。BLE 扫描需要，理由同 [locationOn]。
  final bool locationPermission;

  /// 系统版本：决定走哪一套蓝牙权限模型，排查时必须知道。
  final int sdkInt;
  final String release;

  /// 不可用时的原文，直接画到页面上。
  final String reason;

  /// **每一道门都开着**才谈得上扫得到东西。
  ///
  /// 少判任何一条的后果都一样：扫描静默为空，而页面上显示的是「附近没有设备」——
  /// 把"我们这边没配好"说成了"设备有问题"，正好把排查方向带反。
  bool get usable =>
      available &&
      supported &&
      enabled &&
      locationOn &&
      scanPermission &&
      locationPermission;

  static const BleAvailability unknown = BleAvailability(
    available: false,
    supported: false,
    enabled: false,
    reason: '尚未探测',
  );
}

/// BLE 扫描看到的一台设备（涂鸦 `ScanDeviceBean`）。
///
/// 这条发现通道的意义：Wi-Fi 扫描受 Android 配额限制（前台每 2 分钟 4 次），设备上电
/// 到热点广播出来还要几十秒，两头一凑就是「搜索不及时」；**BLE 不受那条约束**，双模
/// 设备一上电就在广播。
class BleDevice {
  const BleDevice({
    required this.uuid,
    required this.name,
    required this.mac,
    required this.productId,
    required this.rssi,
    required this.bound,
    required this.supportWifiList,
    this.address = '',
    this.id = '',
    this.configType = '',
    this.providerName = '',
    this.deviceType = 0,
    this.flag = 0,
    this.seq = 0,
    this.rawText = '',
  });

  factory BleDevice.fromMap(Map<Object?, Object?> raw) => BleDevice(
    uuid: raw['uuid']?.toString() ?? '',
    name: raw['name']?.toString() ?? '',
    mac: raw['mac']?.toString() ?? '',
    address: raw['address']?.toString() ?? '',
    productId: raw['productId']?.toString() ?? '',
    rssi: (raw['rssi'] as num?)?.toInt() ?? 0,
    bound: raw['bound'] == true,
    supportWifiList: raw['supportWifiList'] == true,
    id: raw['id']?.toString() ?? '',
    configType: raw['configType']?.toString() ?? '',
    providerName: raw['providerName']?.toString() ?? '',
    deviceType: (raw['deviceType'] as num?)?.toInt() ?? 0,
    flag: (raw['flag'] as num?)?.toInt() ?? 0,
    seq: (raw['seq'] as num?)?.toInt() ?? 0,
    rawText: raw['raw']?.toString() ?? '',
  );

  /// 设备的 BLE uuid。**查 Wi-Fi 列表与双模配网都靠它**：原生按它取回自己缓存的
  /// `ScanDeviceBean`（那个对象过不了方法通道），再喂给 `queryDeviceConfigState`
  /// 与 `IMultiModeActivator.startActivator`。
  final String uuid;
  final String name;
  final String mac;
  final String productId;

  /// 信号强度 dBm，越接近 0 越强。
  final int rssi;

  /// 已经绑在某个账号下。配网页要的是没绑的那些。
  final bool bound;

  /// 设备愿意把**它自己扫到的** Wi-Fi 列表报上来（固件 TuyaOS ≥ 3.6.1，
  /// 对应 `CombosFlagCapability.SCAN_WIFI` 那一位）。
  ///
  /// **false 时不要去调 `queryDeviceWifiList`**：老固件不认这条命令，只会让用户
  /// 干等一次超时，回落到手机的 Wi-Fi 扫描反而快。
  final bool supportWifiList;

  /// 蓝牙地址。**和 [mac] 是两个字段**：双模配网真正拿去连的是 address，
  /// 之前把两者合并上报，address 为空时看不出来。
  final String address;

  final String id;
  final String configType;
  final String providerName;
  final int deviceType;

  /// 这是本轮第几次 `onResult` 回调。**用来判断"SDK 到底有没有在回报"**：
  /// 列表为空而 seq 一直在涨，说明扫描是活的、只是我们没留住；两者都是 0 才是真的没回调。
  final int seq;

  /// SDK 那个 bean 的原样 `toString()`。
  ///
  /// ⚠️ 上面那些字段是按常见 getter 名猜着读的；万一这一版 SDK 字段名不一样，全都会是空，
  /// 而页面上看不出为什么。有了这一条，真机上一眼能看到 SDK 究竟给了什么。
  final String rawText;

  /// 能力位原值。真机上排查 [supportWifiList] 为什么是 false 时要看它。
  final int flag;

  /// 去重用的稳定键。
  ///
  /// ⚠️ **不能只用 uuid**：广播里未必带 uuid，而按 uuid 去重会让所有没有 uuid 的设备
  /// 挤成一条、甚至被整条丢掉（2026-09-11 真机"一台都扫不到"的原因之一就是仓库层
  /// 把 uuid 为空的直接 return null 了）。按 uuid → mac → address → id 依次退。
  String get key {
    for (final candidate in <String>[uuid, mac, address, id]) {
      if (candidate.trim().isNotEmpty) return candidate.trim();
    }
    return 'seq-$seq';
  }

  /// 页面上怎么称呼这一台。
  ///
  /// BLE 广播里的 name 经常是空的（很多固件根本不放），退到 mac 尾号——
  /// 「设备 3F:A2」也比一个空行强。
  String get label {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final tail = mac.replaceAll(':', '');
    if (tail.length >= 4) return '设备 ${tail.substring(tail.length - 4)}';
    return uuid.isNotEmpty ? '设备 $uuid' : '未命名设备';
  }

  /// 与 [WifiNetwork.signalBars] 同一套档位，页面画格数用。
  int get signalBars => switch (rssi) {
    >= -55 => 4,
    >= -65 => 3,
    >= -75 => 2,
    _ => 1,
  };
}

/// 云端按 pid / uuid / mac 查回来的**产品信息**。
///
/// BLE 广播里常常没有名字，页面上一行只有 `mac + pid + rssi`，人没法判断哪一台是花盆。
/// 拿 pid 去云端换回产品名之后，列表才真的能"看出有没有"。
class BleProductInfo {
  const BleProductInfo({this.name = '', this.icon = '', this.raw = ''});

  factory BleProductInfo.fromMap(Map<Object?, Object?> map) => BleProductInfo(
    name: map['name']?.toString() ?? '',
    icon: map['icon']?.toString() ?? '',
    raw: map['raw']?.toString() ?? '',
  );

  final String name;
  final String icon;

  /// 认不出字段时的原样 `toString()`。真机上一眼能看出 SDK 给的是什么 bean。
  final String raw;

  bool get isEmpty => name.trim().isEmpty;
}

/// 设备**自己扫到的**一个 Wi-Fi（走 BLE 问它要的那份列表）。
///
/// 比手机扫到的准：手机在客厅收得到的网络，窗台上的花盆未必够得着，让用户从手机的
/// 列表里挑，挑中一个设备连不上的网络是很常见的失败。
class DeviceWifiNetwork {
  const DeviceWifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.sec,
    this.raw = '',
  });

  factory DeviceWifiNetwork.fromMap(Map<Object?, Object?> item) =>
      DeviceWifiNetwork(
        ssid: item['ssid']?.toString() ?? '',
        rssi: (item['rssi'] as num?)?.toInt() ?? 0,
        sec: (item['sec'] as num?)?.toInt() ?? 0,
        raw: item['raw']?.toString() ?? '',
      );

  final String ssid;
  final int rssi;

  /// 加密方式，0 = 开放网络。
  final int sec;

  /// 原生那一版 bean 的 `toString()`。字段名对不上时，真机上一眼就能看出
  /// SDK 到底给的是什么——比在代码里猜快得多。
  final String raw;

  bool get needsPassword => sec != 0;

  int get signalBars => switch (rssi) {
    >= -55 => 4,
    >= -65 => 3,
    >= -75 => 2,
    _ => 1,
  };
}

/// 配网进度，对应 `设备配网-配网中的步骤` 那三步。
///
/// 一次 AP 配网内部是「取令牌 → 连热点 → 下发凭据 → 等云端」，用户能理解的是前端画的
/// 这三步，所以取令牌和连热点合成「连接设备」一步。
///
/// 2026-09-11 从五步**改回三步**：五步那一版是照智能生活截图（`docs/配网1.jpg`）做的，
/// 后两步依赖涂鸦「新流程」的 `queryDeviceConfigState` + `onStep` 回调；那条路已经整条
/// 删掉（见 `FlowerpotState.pairViaHotspot`），步数也就跟着回到原来的三步。
enum PairingStage {
  /// 没有配网在跑。
  idle,

  /// 取配网令牌、把手机连到设备热点上。
  connectingDevice,

  /// 已经连上热点，正在把 Wi-Fi 凭据下发给设备。
  sendingWifi,

  /// 凭据已下发，设备正在连路由器并注册到云端。
  connectingCloud;

  /// 这一步在界面上的名字。
  String get label => switch (this) {
    PairingStage.idle => '准备中',
    PairingStage.connectingDevice => '连接设备',
    PairingStage.sendingWifi => '发送Wi-Fi信息',
    PairingStage.connectingCloud => '连接云端',
  };

  /// 每一步在进度页上那句说明。
  ///
  /// 必要的话都写在这三行里，不再另外弹框：配网期间已经有一个系统的热点连接确认框
  /// （Android 10+ 的 `WifiNetworkSpecifier` 必弹，App 关不掉，涂鸦 2026-09-11 书面
  /// 确认无绕过方案），再叠自己的 toast 和遮罩，用户根本分不清哪个是要他操作的。
  String get hint => switch (this) {
    PairingStage.idle => '',
    PairingStage.connectingDevice => '系统若弹出连接热点的确认框，请点「连接」',
    // 2026-09-14 产品定稿文案。
    PairingStage.sendingWifi => '正在把Wi-Fi信息同步给设备，请勿离开本页面',
    PairingStage.connectingCloud => '设备正在连接路由器并注册到云端',
  };

  /// 界面上按顺序画出来的三步。
  static const List<PairingStage> steps = <PairingStage>[
    PairingStage.connectingDevice,
    PairingStage.sendingWifi,
    PairingStage.connectingCloud,
  ];
}

/// Result of a nearby-network scan, used to check whether the device hotspot
/// is up and whether the phone itself sits on 2.4 GHz.
///
/// [networks] is empty on platforms that cannot enumerate access points — iOS
/// only reports the network the phone is on — so screens have to treat "no
/// networks" as "unknown", never as "no device nearby".
/// 一次固件检查的结果。
///
/// 两个版本号必须来自同一条 OTA 记录：设备可能有 MCU、Wi-Fi 模块等几个可升级
/// 组件，各自版本号不同。以前「当前版本」取的是设备列表里的字段、「新版本」取
/// 的是 OTA 记录，两者根本不是同一个东西，弹窗上两行对不上。
/// 涂鸦平台上给这次固件配的「升级方式」，即 OTA 记录的 `upgradeType`。
///
/// 取值 2026-09-15 解包 Android SDK 7.5.1 核对：`UpgradeInfoBean.UPGRADE_TYPE_REMIND = 0`、
/// `UPGRADE_TYPE_FORCED = 2`、`UPGRADE_TYPE_CHECKING = 3`；iOS
/// `ThingSmartFirmwareUpgradeModel.upgradeType` 同一套。平台上的说明：
/// - App 提醒升级：用户进入设备面板主动提醒，用户可以选择是否升级；
/// - App 强制升级：升级提醒主动推送给用户，用户无选择权利，必须升级；
/// - App 检测升级：不主动推送，要用户主动发起版本检测才看得到。
enum FirmwareUpgradeType {
  remind,
  force,
  check;

  /// 认不出的值（含老原生包不回这个字段）按「检测升级」处理：只亮小红点、不弹窗，
  /// 也就是这个字段加进来之前的行为。
  static FirmwareUpgradeType fromTuya(Object? raw) {
    final value = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    return switch (value) {
      0 => FirmwareUpgradeType.remind,
      2 => FirmwareUpgradeType.force,
      _ => FirmwareUpgradeType.check,
    };
  }
}

class FirmwareUpdate {
  const FirmwareUpdate({
    required this.version,
    this.currentVersion,
    this.upgradeType = FirmwareUpgradeType.check,
  });

  /// 待安装的新版本号。
  final String version;

  /// 涂鸦在同一条 OTA 记录里报的「该组件当前版本」，SDK 没给时为 null。
  final String? currentVersion;

  /// 平台上配的升级方式，决定设备页弹不弹提醒，见 [FirmwareUpgradeType]。
  final FirmwareUpgradeType upgradeType;
}

class WifiScan {
  const WifiScan({
    required this.networks,
    this.current,
    this.currentFrequency,
    this.throttled = false,
    this.ageMs,
  });

  final List<WifiNetwork> networks;
  final String? current;
  final int? currentFrequency;

  /// 这一轮**没有真的扫**，答的是上一次的缓存。
  ///
  /// Android 9 起前台应用每 2 分钟只允许 4 次 `startScan`，超了就直接拒绝。被拒时
  /// 列表里当然没有用户刚开机的那台设备——把它当成「附近没有设备」是错的，页面得
  /// 改成等配额回来再扫。iOS 不枚举附近网络，这里恒为 false。
  final bool throttled;

  /// 缓存里最新一条结果的年龄（毫秒）；平台不报时为 null。
  ///
  /// 和 [throttled] 互为佐证：有些机型限流时 `startScan` 照样返回 true、只是不
  /// 重扫，这时只有年龄看得出来这一轮是白跑的。
  final int? ageMs;

  /// Null when the platform does not report a band. A non-positive frequency
  /// is the "not connected" answer some Android builds give, and is unknown
  /// rather than 5 GHz.
  bool? get currentIs24g {
    final frequency = currentFrequency;
    if (frequency == null || frequency <= 0) return null;
    return frequency >= 2400 && frequency < 2500;
  }

  /// Whether the phone itself sits on a planter hotspot, which is what AP
  /// provisioning needs right before [PairingRequest] is handed to the SDK.
  bool get currentIsDeviceHotspot {
    final ssid = current;
    return ssid != null && WifiNetwork.isDeviceHotspotName(ssid);
  }

  /// Planters waiting in AP provisioning mode, strongest first.
  ///
  /// 2026-09-11 之前这里写着「产品没有 BLE 发现、SDK 也没有扫描 API」——**两句都是
  /// 错的**：`ThingHomeSdk.getBleOperator().startLeScan(...)` 一直都在（已解包核对），
  /// 双模设备也在广播 BLE。现在 BLE 是一条并行的发现通道（见 [BleDevice]），这份
  /// Wi-Fi 热点列表是设备不支持 BLE 时的那条。
  List<WifiNetwork> get deviceHotspots =>
      _strongestPerSsid(networks.where((item) => item.looksLikeDeviceHotspot));

  /// The rest of the scan, as a fallback pick list for the pairing pages:
  /// everything [deviceHotspots] did not claim, minus 5 GHz entries the
  /// planter's AP can never be, strongest first.
  ///
  /// [WifiNetwork.isDeviceHotspotName] is a whitelist of SSID prefixes, so a
  /// planter naming its hotspot outside it is invisible to the search and
  /// selection pages while the SDK debug console — which prints the raw scan —
  /// shows it. These rows are how the user picks that device by name instead
  /// of being told there is none.
  List<WifiNetwork> get otherNetworks => _strongestPerSsid(
    networks.where(
      // A missing/zero frequency is "unknown band", not 5 GHz, and has to stay
      // in the list.
      (item) => !item.looksLikeDeviceHotspot && item.frequency < 2500,
    ),
  );

  /// Routers the planter can be asked to join: 2.4 GHz only, device hotspots
  /// removed, strongest first.
  List<WifiNetwork> get routerNetworks => _strongestPerSsid(
    networks.where((item) => item.is24g && !item.looksLikeDeviceHotspot),
  );

  /// One entry per SSID, keeping the strongest reading. A real scan returns the
  /// same network once per band and per access point.
  static List<WifiNetwork> _strongestPerSsid(Iterable<WifiNetwork> items) {
    final byName = <String, WifiNetwork>{};
    for (final network in items) {
      if (network.ssid.isEmpty) continue;
      final known = byName[network.ssid];
      if (known == null || network.level > known.level) {
        byName[network.ssid] = network;
      }
    }
    final sorted = byName.values.toList(growable: false)
      ..sort((a, b) => b.level.compareTo(a.level));
    return List<WifiNetwork>.unmodifiable(sorted);
  }
}

class ActionResult {
  const ActionResult(this.success, this.message, {this.code});

  final bool success;
  final String message;

  /// Failure code behind [message], such as `sdk_unavailable`,
  /// `credentials_missing` or a code raised by the Tuya SDK itself. Product
  /// pages show only [message]; the SDK debug console needs the code to tell a
  /// platform configuration problem apart from a rejected account.
  final String? code;
}
