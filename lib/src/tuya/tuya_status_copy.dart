import 'tuya_models.dart';

/// 一条状态功能点的取值在界面上怎么写：状态页顶部的短标签，加它下面那段说明。
class DeviceStatusCopy {
  const DeviceStatusCopy(this.label, this.description);

  /// 状态页顶部、首页状态卡片上的那几个字。
  final String label;

  /// 短标签下面那段说明。
  final String description;
}

/// DP 107 / 108 / 113 / 115 四条状态功能点的文案，以及设备没上报时的兜底判据。
///
/// 键就是涂鸦平台导出的枚举值本身（`shortage`/`drinking`/`watery` 等），可以和
/// `docs/智能花盆test(yciq4kssu1fv8umn)_09_07.xlsx` 逐行对照。文案只有这一份：
/// 状态页顶部和首页的状态卡片读同一张表，同一台设备不会再一边写「喝水中」一边
/// 写「偏湿」。
///
/// 113 和 115 在 Dart 侧共用 [ComfortLevel]（low/suitable/high），但设备的枚举名
/// 和文案都不一样（cold/suitable/heat 对 dry/suitable/damp），所以分成两张表。
///
/// 多语种：设置页目前提供简体中文和英文两种（`FlowerpotState.languageCode`）。
/// 每条状态都备了中英两份文案，取用走 [waterNeedsCopy] 这类按语言查表的方法，
/// 没有对应语言时回落简体中文。整个 App 还没有引入 `flutter_localizations`/arb，
/// 这里是这批文案自己的一张小表，不是全局方案。
abstract final class TuyaStatusCopy {
  /// `water_needs_status` (107)：shortage / drinking / watery。
  static const waterNeeds = <WaterNeedsStatus, DeviceStatusCopy>{
    WaterNeedsStatus.shortage: DeviceStatusCopy(
      '口渴了',
      '水仓快见底了，根系快吸不到水了，该加水啦。',
    ),
    WaterNeedsStatus.drinking: DeviceStatusCopy(
      '喝水中',
      '植物正在从水仓中吸取水分，请保持当前状态。',
    ),
    WaterNeedsStatus.watery: DeviceStatusCopy(
      '喝撑了',
      '水仓里水太多，根系透不过气，先别加水了，通通风吧。',
    ),
  };

  /// `lighting_condition` (108)：shortage / good / very_good。
  static const lighting = <LightingCondition, DeviceStatusCopy>{
    LightingCondition.shortage: DeviceStatusCopy(
      '晒不够',
      '光线有点弱，光合作用使不上劲，搬到亮堂点的地方吧。',
    ),
    LightingCondition.good: DeviceStatusCopy(
      '正合适',
      '光线刚刚好，光合作用很顺畅，继续保持。',
    ),
    LightingCondition.veryGood: DeviceStatusCopy(
      '晒太阳中',
      '阳光充足，光合作用正旺盛，继续保持。',
    ),
  };

  /// `air_temperature_status` (113)：cold / suitable / heat。
  static const airTemperature = <ComfortLevel, DeviceStatusCopy>{
    ComfortLevel.low: DeviceStatusCopy(
      '有点冷',
      '温度偏低了，植物不太爱长，给它暖暖身子吧。',
    ),
    ComfortLevel.suitable: DeviceStatusCopy(
      '正舒适',
      '温度刚刚好，植物正舒服地长着呢，继续保持。',
    ),
    ComfortLevel.high: DeviceStatusCopy(
      '有点热',
      '温度偏高了，叶子容易蔫，挪到阴凉点的地方吧。',
    ),
  };

  /// `air_humidity_status` (115)：dry / suitable / damp。
  static const airHumidity = <ComfortLevel, DeviceStatusCopy>{
    ComfortLevel.low: DeviceStatusCopy(
      '太干了',
      '空气干巴巴的，叶子容易失去水分，喷点水雾吧。',
    ),
    ComfortLevel.suitable: DeviceStatusCopy(
      '正舒服',
      '湿度刚刚好，叶子呼吸很顺畅，继续保持。',
    ),
    ComfortLevel.high: DeviceStatusCopy(
      '太潮了',
      '空气湿乎乎的，容易滋生细菌，多通通风吧。',
    ),
  };

  /// 英文文案，键与上面四张中文表一一对应。
  static const waterNeedsEn = <WaterNeedsStatus, DeviceStatusCopy>{
    WaterNeedsStatus.shortage: DeviceStatusCopy(
      'Thirsty',
      'The tank is nearly empty and the roots can barely drink. Time to add '
          'water.',
    ),
    WaterNeedsStatus.drinking: DeviceStatusCopy(
      'Drinking',
      'The plant is taking water from the tank. Keep things as they are.',
    ),
    WaterNeedsStatus.watery: DeviceStatusCopy(
      'Too full',
      'There is too much water for the roots to breathe. Hold off on '
          'refilling and let it air out.',
    ),
  };

  static const lightingEn = <LightingCondition, DeviceStatusCopy>{
    LightingCondition.shortage: DeviceStatusCopy(
      'Needs light',
      'The light is a little weak for photosynthesis. Move it somewhere '
          'brighter.',
    ),
    LightingCondition.good: DeviceStatusCopy(
      'Just right',
      'The light is just right and photosynthesis is running smoothly. Keep '
          'it that way.',
    ),
    LightingCondition.veryGood: DeviceStatusCopy(
      'Sunbathing',
      'Plenty of sun and photosynthesis is in full swing. Keep it that way.',
    ),
  };

  static const airTemperatureEn = <ComfortLevel, DeviceStatusCopy>{
    ComfortLevel.low: DeviceStatusCopy(
      'A bit cold',
      'It is colder than the plant likes to grow in. Warm it up a little.',
    ),
    ComfortLevel.suitable: DeviceStatusCopy(
      'Comfortable',
      'The temperature is just right and the plant is growing happily. Keep '
          'it that way.',
    ),
    ComfortLevel.high: DeviceStatusCopy(
      'A bit hot',
      'It is hotter than the leaves like. Move it somewhere cooler.',
    ),
  };

  static const airHumidityEn = <ComfortLevel, DeviceStatusCopy>{
    ComfortLevel.low: DeviceStatusCopy(
      'Too dry',
      'The air is dry and the leaves lose water easily. Give them a light '
          'mist.',
    ),
    ComfortLevel.suitable: DeviceStatusCopy(
      'Comfortable',
      'The humidity is just right and the leaves breathe easily. Keep it '
          'that way.',
    ),
    ComfortLevel.high: DeviceStatusCopy(
      'Too damp',
      'The air is muggy and bacteria thrive in it. Let it air out more.',
    ),
  };

  /// 设备没上报 113 时用的舒适区间（摄氏）。温度状态页和首页养护建议共用这一份，
  /// 免得两处各写一个阈值、同一台设备在两个页面得出不同的冷热判断。
  static const double comfortableLowCelsius = 18;
  static const double comfortableHighCelsius = 28;

  /// 除英文外一律回落简体中文——App 里还有繁体和日文的语言码，但这批文案没有
  /// 对应译文，宁可显示中文也不显示占位符。
  static bool _isEnglish(String language) =>
      language.trim().toLowerCase().startsWith('en');

  /// 按界面语言取 107 的文案。
  static DeviceStatusCopy waterNeedsCopy(
    WaterNeedsStatus value, {
    String language = 'zh',
  }) =>
      (_isEnglish(language) ? waterNeedsEn[value] : null) ??
      waterNeeds[value]!;

  /// 按界面语言取 108 的文案。
  static DeviceStatusCopy lightingCopy(
    LightingCondition value, {
    String language = 'zh',
  }) => (_isEnglish(language) ? lightingEn[value] : null) ?? lighting[value]!;

  /// 按界面语言取 113 的文案。
  static DeviceStatusCopy airTemperatureCopy(
    ComfortLevel value, {
    String language = 'zh',
  }) =>
      (_isEnglish(language) ? airTemperatureEn[value] : null) ??
      airTemperature[value]!;

  /// 按界面语言取 115 的文案。
  static DeviceStatusCopy airHumidityCopy(
    ComfortLevel value, {
    String language = 'zh',
  }) =>
      (_isEnglish(language) ? airHumidityEn[value] : null) ??
      airHumidity[value]!;

  /// 设备没上报 107 时按水仓水位兜底。
  ///
  /// 三档文案说的都是水仓（「水仓快见底」「水仓里水太多」），所以兜底也看 DP 105
  /// 而不是土壤湿度。两端的阈值是按 105 的量程 0–200 mL 猜的，只在设备没上报 107
  /// 时起作用——设备报了就以设备为准。
  static WaterNeedsStatus waterNeedsFor(int waterLevel) => switch (waterLevel) {
    < 20 => WaterNeedsStatus.shortage,
    > 150 => WaterNeedsStatus.watery,
    _ => WaterNeedsStatus.drinking,
  };

  /// 设备没上报 108 时按照度兜底。
  static LightingCondition lightingFor(int illuminance) =>
      switch (illuminance) {
        < 200 => LightingCondition.shortage,
        > 1200 => LightingCondition.veryGood,
        _ => LightingCondition.good,
      };

  /// 设备没上报 115 时按相对湿度兜底。
  static ComfortLevel humidityFor(int relativeHumidity) =>
      switch (relativeHumidity) {
        < 40 => ComfortLevel.low,
        > 70 => ComfortLevel.high,
        _ => ComfortLevel.suitable,
      };

  /// 设备没上报 113 时按温度兜底。[low] 和 [high] 要先换算成设备当前上报的单位，
  /// 见 [DeviceControlSettings.temperatureFromCelsius]。
  static ComfortLevel temperatureFor(
    double reading, {
    required double low,
    required double high,
  }) {
    if (reading < low) return ComfortLevel.low;
    if (reading > high) return ComfortLevel.high;
    return ComfortLevel.suitable;
  }
}
