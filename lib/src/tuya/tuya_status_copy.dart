import 'tuya_models.dart';

/// 一条状态功能点的取值在界面上怎么写：状态页顶部的短标签，加它下面那段说明。
class DeviceStatusCopy {
  const DeviceStatusCopy(this.label, this.description, this.advice);

  /// 状态页顶部、首页状态卡片上的那几个字。
  final String label;

  /// 短标签下面那段说明。
  final String description;

  /// 状态详情页下方那张「养护建议」卡片的正文。2026-09-08 起由产品统一给稿，
  /// 直接写在这张表里，不再从接口取。
  final String advice;
}

/// DP 107 / 108 / 113 / 115 四条状态功能点的文案，以及设备没上报时的兜底判据。
///
/// 键就是涂鸦平台导出的枚举值本身（`shortage`/`drinking`/`watery` 等），可以和
/// `assets/智能花盆test(yciq4kssu1fv8umn)_09_16.xlsx` 逐行对照。文案只有这一份：
/// 状态页顶部和首页的状态卡片读同一张表，同一台设备不会再一边写「喝水中」一边
/// 写「偏湿」。
///
/// **2026-09-16 产品重写了这 12 条**：短标签、说明和建议全部换成植物第一人称，
/// 说明只留一句话，建议是「请用户做什么」。改的是措辞不是判据——枚举到档位的
/// 对应关系没动，只有 108 的 `very_good` 从「晒得正好」改口成「太晒了」。
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
      '有点缺水了。',
      '水仓快见底了，给我补一点水吧。',
    ),
    WaterNeedsStatus.drinking: DeviceStatusCopy(
      '喝水中',
      '正在慢慢吸收水分。',
      '让我喝一会儿，先不用加水。',
    ),
    WaterNeedsStatus.watery: DeviceStatusCopy(
      '快淹了',
      '水好像有点多。',
      '让我透透气，暂时先别加水了。',
    ),
  };

  /// `lighting_condition` (108)：shortage / good / very_good。
  ///
  /// ⚠️ `very_good` 在 2026-09-16 这版文案里说的是「太晒了」，不再是「晒得正好」。
  /// 枚举名没变，变的只是产品对它的解读：光照三档是 弱 / 正好 / 过强。
  static const lighting = <LightingCondition, DeviceStatusCopy>{
    LightingCondition.shortage: DeviceStatusCopy(
      '天黑了吗',
      '今天的阳光好像不太够。',
      '光线有点弱，换个明亮一点的位置吧。',
    ),
    LightingCondition.good: DeviceStatusCopy(
      '阳光明媚',
      '今天的阳光正好。',
      '光线充足又柔和，待在这里很舒服。',
    ),
    LightingCondition.veryGood: DeviceStatusCopy(
      '太晒了',
      '阳光有点强。',
      '晒得有些过了，帮我避开一点直射光吧。',
    ),
  };

  /// `air_temperature_status` (113)：cold / suitable / heat。
  static const airTemperature = <ComfortLevel, DeviceStatusCopy>{
    ComfortLevel.low: DeviceStatusCopy(
      '有点冷',
      '温度有点低。',
      '给我找个暖和一点的地方吧。',
    ),
    ComfortLevel.suitable: DeviceStatusCopy(
      '温度适宜',
      '这个温度很舒服。',
      '不冷也不热，正适合待着。',
    ),
    ComfortLevel.high: DeviceStatusCopy(
      '有点热',
      '温度有点高。',
      '带我去凉快一点的地方吧。',
    ),
  };

  /// `air_humidity_status` (115)：dry / suitable / damp。
  static const airHumidity = <ComfortLevel, DeviceStatusCopy>{
    ComfortLevel.low: DeviceStatusCopy(
      '太干了',
      '空气里的水分有点少。',
      '叶片容易失去水分，可以给我一点水雾。',
    ),
    ComfortLevel.suitable: DeviceStatusCopy(
      '很温润',
      '空气湿润又舒服。',
      '现在的状态刚刚好。',
    ),
    ComfortLevel.high: DeviceStatusCopy(
      '太潮了',
      '空气有点潮湿。',
      '感觉有些闷，帮我通通风吧。',
    ),
  };

  /// 英文文案，键与上面四张中文表一一对应。
  static const waterNeedsEn = <WaterNeedsStatus, DeviceStatusCopy>{
    WaterNeedsStatus.shortage: DeviceStatusCopy(
      'Thirsty',
      'I am running a little low on water.',
      'The tank is nearly empty. Please top me up a little.',
    ),
    WaterNeedsStatus.drinking: DeviceStatusCopy(
      'Drinking',
      'I am slowly taking the water in.',
      'Let me drink for a while. No need to add more just yet.',
    ),
    WaterNeedsStatus.watery: DeviceStatusCopy(
      'Nearly flooded',
      'That looks like a little too much water.',
      'Let me air out. Please hold off on watering for now.',
    ),
  };

  static const lightingEn = <LightingCondition, DeviceStatusCopy>{
    LightingCondition.shortage: DeviceStatusCopy(
      'Is it dark?',
      'There does not seem to be enough sun today.',
      'The light is a little weak. Move me somewhere brighter.',
    ),
    LightingCondition.good: DeviceStatusCopy(
      'Lovely sun',
      'The sunshine is just right today.',
      'The light is plentiful and gentle. It feels good right here.',
    ),
    LightingCondition.veryGood: DeviceStatusCopy(
      'Too sunny',
      'The sun is a little strong.',
      'That is more sun than I need. Please keep me out of direct light.',
    ),
  };

  static const airTemperatureEn = <ComfortLevel, DeviceStatusCopy>{
    ComfortLevel.low: DeviceStatusCopy(
      'A bit cold',
      'It is a little cool in here.',
      'Please find me a warmer spot.',
    ),
    ComfortLevel.suitable: DeviceStatusCopy(
      'Just right',
      'This temperature feels lovely.',
      'Not too cold, not too warm. Perfect for staying put.',
    ),
    ComfortLevel.high: DeviceStatusCopy(
      'A bit hot',
      'It is a little warm in here.',
      'Please take me somewhere cooler.',
    ),
  };

  static const airHumidityEn = <ComfortLevel, DeviceStatusCopy>{
    ComfortLevel.low: DeviceStatusCopy(
      'Too dry',
      'There is not much moisture in the air.',
      'My leaves lose water easily. A little mist would help.',
    ),
    ComfortLevel.suitable: DeviceStatusCopy(
      'Nicely humid',
      'The air is moist and comfortable.',
      'Things are just right as they are.',
    ),
    ComfortLevel.high: DeviceStatusCopy(
      'Too damp',
      'The air is a little humid.',
      'It feels stuffy in here. Please let some air through.',
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
