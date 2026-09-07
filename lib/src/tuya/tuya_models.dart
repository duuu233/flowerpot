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

/// `plant_confirm` (162)：设备与 App 之间关于「盆里到底是哪种植物」的握手。
///
/// 这条在 09-07 的导出里是数值，不是开关：设备发现盆里的植物和下发的 116 不是
/// 同一种时先只报 [mismatch]，**不上报新的植物标识**，等 App 把用户的处置写回来
/// 才继续——[confirmed] 让设备改用盆里那株并重新上报 116，[ignored] 让设备保持
/// 旧的 116 再回报一次。
enum PlantConfirmState {
  /// 0 正常：设备判定一致。
  normal(0),

  /// 1 异常：设备判定不一致，等 App 处置。
  mismatch(1),

  /// 2 确认：以花盆里的植物为准。
  confirmed(2),

  /// 3 忽略：保留 App 现在的植物。
  ignored(3);

  const PlantConfirmState(this.dpValue);

  /// 上报和下发用的数值。
  final int dpValue;

  /// 设备没上报过这条时按 [normal] 处理：「没报异常」不等于「异常」，默认成
  /// [mismatch] 会让 09-07 之前固件的设备每次进详情页都被问一次。
  static PlantConfirmState fromDp(Object? raw) {
    final value = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    return switch (value) {
      1 => mismatch,
      2 => confirmed,
      3 => ignored,
      _ => normal,
    };
  }
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
  const DeviceUpdate.changed(SmartPlanterDevice this.device) : removedId = null;

  /// The device left the account — unbound from another phone, or reset.
  const DeviceUpdate.removed(String this.removedId) : device = null;

  final SmartPlanterDevice? device;
  final String? removedId;
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
  });

  final String deviceId;
  final OtaStatus status;

  /// 0–100，仅 [OtaStatus.running] 时有值。
  final int? percent;

  /// 失败原因，仅 [OtaStatus.failed] 时有值。
  final String? message;
}

enum OtaStatus { running, success, failed }

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

  /// Backend ids used by the plant APIs. Static fallback plants leave these
  /// null and can still be used by the offline/demo flow.
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
    difficultyMaintenance: difficultyMaintenance,
    plantType: plantType,
  );
}

/// The plants the app can offer.
///
/// Every entry has artwork in `AppAssets.plantImages`; a plant without artwork
/// is not listed, because the picker shows the image as the card. Keep the two
/// in step when adding one.
abstract final class PlantCatalog {
  static const items = <PlantProfile>[
    PlantProfile(
      id: 'pilea_cadierei',
      name: '冷水花',
      latinName: 'Pilea cadierei',
      color: Color(0xFF4D8B55),
      moistureTarget: 68,
      lightTarget: 120,
      tip: '喜湿润明亮环境，适合室内桌面或半阴环境栽培。',
      tuyaIdentifier: 'pilea_cadierei',
    ),
    PlantProfile(
      id: 'pothos',
      name: '绿萝',
      latinName: 'Epipremnum aureum',
      color: Color(0xFF65A765),
      moistureTarget: 62,
      lightTarget: 100,
      tip: '耐阴但不耐积水，保持通风有助于新叶生长。',
      tuyaIdentifier: 'pothos',
    ),
    PlantProfile(
      id: 'ivy',
      name: '常春藤',
      latinName: 'Hedera helix',
      color: Color(0xFF527B48),
      moistureTarget: 58,
      lightTarget: 150,
      tip: '适合明亮散射光，保持盆土微润并注意通风。',
      tuyaIdentifier: 'ivy',
    ),
    PlantProfile(
      id: 'monstera',
      name: '龟背竹',
      latinName: 'Monstera deliciosa',
      color: Color(0xFF2F7D5D),
      moistureTarget: 58,
      lightTarget: 140,
      tip: '喜欢明亮散射光，表层土壤微干后再浇水。',
      tuyaIdentifier: 'monstera',
    ),
    PlantProfile(
      id: 'bird_of_paradise',
      name: '天堂鸟',
      latinName: 'Strelitzia reginae',
      color: Color(0xFF4F8C54),
      moistureTarget: 55,
      lightTarget: 260,
      tip: '需要充足的柔和光照，生长期保持土壤均匀湿润。',
      tuyaIdentifier: 'bird_of_paradise',
    ),
    PlantProfile(
      id: 'china_doll',
      name: '幸福树',
      latinName: 'Radermachera sinica',
      color: Color(0xFF367C46),
      moistureTarget: 60,
      lightTarget: 180,
      tip: '喜温暖明亮环境，避免积水和长时间强光直射。',
      tuyaIdentifier: 'china_doll',
    ),
  ];

  static PlantProfile byId(String? id) =>
      items.firstWhere((plant) => plant.id == id, orElse: () => items.first);

  static PlantProfile? findById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final plant in items) {
      if (plant.id == id) return plant;
    }
    return null;
  }

  static PlantProfile? findByTuyaIdentifier(String? identifier) {
    final normalized = identifier?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final plant in items) {
      if (plant.tuyaIdentifier.toLowerCase() == normalized) return plant;
    }
    return null;
  }
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

  /// `plant_detect_switch`：自动检测植物的总开关，关掉之后设备不再比对盆里的
  /// 植物，也就不会再报 `plant_confirm` 异常。
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
    this.plantConfirm = PlantConfirmState.normal,
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
  final String plantVariety;

  /// `plant_confirm` (162)：设备对「盆里的植物和 [plantVariety] 是不是同一种」
  /// 的判定，以及 App 写回去的处置。取值见 [PlantConfirmState]。
  final PlantConfirmState plantConfirm;

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
/// [mode] 取 `ap` 或 `ez`：
/// - `ap`（默认）手机先连设备自己拉起的热点，再把路由器凭据交给它。Android 10
///   起 App 可以直接发起这个连接（系统弹框确认即可，见 `joinDeviceHotspot`），
///   不必让用户去系统设置，所以步骤并不比 EZ 多。它不受路由器组播策略影响，是
///   实测唯一稳定配上的方式。
/// - `ez` 手机全程连在路由器上广播凭据，看似更省事，但必须处在 2.4G，且很多
///   路由器会过滤组播导致设备收不到；设备也必须处在 EZ 模式（快闪、不拉热点）。
///
/// 没有双模：7.5.1 的 `ActivatorModelEnum` 只提供
/// `THING_AP / THING_EZ / THING_4G_GATEWAY / THING_STATIC_IP / THING_QR`，
/// 实机查询过，不存在 EZ+AP 合一的常量。
class PairingRequest {
  const PairingRequest({
    required this.ssid,
    required this.password,
    this.mode = 'ap',
  });

  final String ssid;
  final String password;
  final String mode;

  bool get isAp => mode == 'ap';
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

/// 配网进度，对应 `设备配网-配网中的步骤` 那三步。
///
/// 一次 AP 配网内部是「取令牌 → 连热点 → 下发凭据 → 等云端」，用户能理解的是
/// 前端画的这三步，所以取令牌和连热点合成「连接设备」一步。
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
class WifiScan {
  const WifiScan({required this.networks, this.current, this.currentFrequency});

  final List<WifiNetwork> networks;
  final String? current;
  final int? currentFrequency;

  /// Null when the platform does not report a band. A non-positive frequency
  /// is the "not connected" answer some Android builds give, and is unknown
  /// rather than 5 GHz.
  bool? get currentIs24g {
    final frequency = currentFrequency;
    if (frequency == null || frequency <= 0) return null;
    return frequency >= 2400 && frequency < 2500;
  }

  /// Whether the phone itself sits on a planter hotspot, which is what AP
  /// provisioning needs right before [PairingRequest] with `mode: 'ap'`.
  bool get currentIsDeviceHotspot {
    final ssid = current;
    return ssid != null && WifiNetwork.isDeviceHotspotName(ssid);
  }

  /// Planters waiting in AP provisioning mode, strongest first. Scanning for
  /// these is the only real evidence the app has that a device entered pairing
  /// state: the product has no BLE discovery and the SDK has no scan API.
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
