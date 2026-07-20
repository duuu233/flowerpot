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
  });

  final String id;
  final String name;
  final String latinName;
  final Color color;
  final int moistureTarget;
  final int lightTarget;
  final String tip;
}

abstract final class PlantCatalog {
  static const items = <PlantProfile>[
    PlantProfile(
      id: 'monstera',
      name: '龟背竹',
      latinName: 'Monstera deliciosa',
      color: Color(0xFF2F7D5D),
      moistureTarget: 58,
      lightTarget: 140,
      tip: '喜欢明亮散射光，表层土壤微干后再浇水。',
    ),
    PlantProfile(
      id: 'pothos',
      name: '绿萝',
      latinName: 'Epipremnum aureum',
      color: Color(0xFF65A765),
      moistureTarget: 62,
      lightTarget: 100,
      tip: '耐阴但不耐积水，保持通风有助于新叶生长。',
    ),
    PlantProfile(
      id: 'rosemary',
      name: '迷迭香',
      latinName: 'Salvia rosmarinus',
      color: Color(0xFF6D8B74),
      moistureTarget: 38,
      lightTarget: 320,
      tip: '偏爱充足光照和干爽土壤，避免频繁浇水。',
    ),
    PlantProfile(
      id: 'basil',
      name: '罗勒',
      latinName: 'Ocimum basilicum',
      color: Color(0xFF78A957),
      moistureTarget: 66,
      lightTarget: 240,
      tip: '生长期需稳定水分和较长光照，及时摘心。',
    ),
    PlantProfile(
      id: 'succulent',
      name: '多肉',
      latinName: 'Echeveria',
      color: Color(0xFF90A98F),
      moistureTarget: 25,
      lightTarget: 280,
      tip: '浇透后充分干燥，避免叶心长期积水。',
    ),
    PlantProfile(
      id: 'mint',
      name: '薄荷',
      latinName: 'Mentha canadensis',
      color: Color(0xFF4C9B70),
      moistureTarget: 70,
      lightTarget: 200,
      tip: '保持土壤湿润并定期修剪，可促进分枝。',
    ),
  ];

  static PlantProfile byId(String? id) =>
      items.firstWhere((plant) => plant.id == id, orElse: () => items.first);
}

class SensorSnapshot {
  const SensorSnapshot({
    required this.waterLevel,
    required this.soilMoisture,
    required this.illuminance,
    required this.ppfd,
    required this.airTemperature,
    required this.relativeHumidity,
  });

  final int waterLevel;
  final int soilMoisture;
  final int illuminance;

  /// Photosynthetic photon flux density in μmol/m²/s.
  ///
  /// The device reports fractional values (for example 5.642), so this must
  /// remain a double all the way through the presentation layer.
  final double ppfd;
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
    this.napEnabled = true,
    this.napPeriod = '12:30-13:30',
    this.nightEnabled = true,
    this.nightPeriod = '23:00-07:00',
    this.weatherService = true,
    this.temperatureUnit = 'celsius',
    this.clockFormat = '24h',
  });

  final bool autoBrightness;
  final bool soundInteraction;
  final int soundSensitivity;
  final bool touchInteraction;
  final int touchSensitivity;
  final bool vibration;
  final bool napEnabled;
  final String napPeriod;
  final bool nightEnabled;
  final String nightPeriod;
  final bool weatherService;
  final String temperatureUnit;
  final String clockFormat;

  DeviceControlSettings copyWith({
    bool? autoBrightness,
    bool? soundInteraction,
    int? soundSensitivity,
    bool? touchInteraction,
    int? touchSensitivity,
    bool? vibration,
    bool? napEnabled,
    String? napPeriod,
    bool? nightEnabled,
    String? nightPeriod,
    bool? weatherService,
    String? temperatureUnit,
    String? clockFormat,
  }) => DeviceControlSettings(
    autoBrightness: autoBrightness ?? this.autoBrightness,
    soundInteraction: soundInteraction ?? this.soundInteraction,
    soundSensitivity: soundSensitivity ?? this.soundSensitivity,
    touchInteraction: touchInteraction ?? this.touchInteraction,
    touchSensitivity: touchSensitivity ?? this.touchSensitivity,
    vibration: vibration ?? this.vibration,
    napEnabled: napEnabled ?? this.napEnabled,
    napPeriod: napPeriod ?? this.napPeriod,
    nightEnabled: nightEnabled ?? this.nightEnabled,
    nightPeriod: nightPeriod ?? this.nightPeriod,
    weatherService: weatherService ?? this.weatherService,
    temperatureUnit: temperatureUnit ?? this.temperatureUnit,
    clockFormat: clockFormat ?? this.clockFormat,
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

  int get companionDays => DateTime.now().difference(boundAt).inDays + 1;

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

class PairingRequest {
  const PairingRequest({
    required this.ssid,
    required this.password,
    this.mode = 'ap',
  });

  final String ssid;
  final String password;
  final String mode;
}

class ActionResult {
  const ActionResult(this.success, this.message);

  final bool success;
  final String message;
}
