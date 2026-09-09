import 'package:flutter/painting.dart';
import 'package:flowerpot/src/tuya/tuya_models.dart';

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

