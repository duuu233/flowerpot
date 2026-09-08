import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';

class PlantDetailArguments {
  const PlantDetailArguments({required this.plant, this.bound = false});

  final PlantProfile plant;
  final bool bound;
}

/// 详情内容全部来自植物列表那一行——`getProductPlantList` 已经把字段带齐了，
/// 主流程不再单独打一次植物详情接口。
class PlantDetailPage extends StatelessWidget {
  const PlantDetailPage({required this.arguments, super.key});

  final PlantDetailArguments arguments;

  PlantProfile get plant => arguments.plant;

  @override
  Widget build(BuildContext context) {
    final data = _PlantDetailData.fromProfile(plant);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '植物详情', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('plant-detail-scroll-view'),
        child: ResponsiveContent(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            32,
            AppSpacing.pageMargin,
            28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PlantSummaryCard(
                plant: plant,
                data: data,
                bound: arguments.bound,
              ),
              const SizedBox(height: 12),
              _PlantBasicInfoCard(plant: plant, data: data),
              const SizedBox(height: 12),
              _PlantCareAdviceCard(items: data.careAdvice),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantSummaryCard extends StatelessWidget {
  const _PlantSummaryCard({
    required this.plant,
    required this.data,
    required this.bound,
  });

  final PlantProfile plant;
  final _PlantDetailData data;
  final bool bound;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 300;
            return SizedBox(
              height: compact ? 245 : 215,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: compact ? 108 : 132,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              // Soft round backdrop, as in the design; the pot
                              // is allowed to overflow it.
                              FractionallySizedBox(
                                widthFactor: .82,
                                heightFactor: .72,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: plant.color.withValues(alpha: .10),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: _PlantDetailArtwork(
                                  plant: plant,
                                  key: const Key('plant-detail-image'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          plant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textStrong,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _BindingChip(bound: bound),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _EnvironmentMetric(
                          assetPath: AppAssets.metricTemperatureIcon,
                          label: '适宜温度',
                          value: data.temperature,
                        ),
                        const SizedBox(height: 7),
                        _EnvironmentMetric(
                          assetPath: AppAssets.statusHumidityIcon,
                          label: '适宜湿度',
                          value: data.humidity,
                        ),
                        const SizedBox(height: 7),
                        _EnvironmentMetric(
                          assetPath: AppAssets.metricLightIcon,
                          label: '光照需求',
                          rating: data.lightRating,
                          warning: true,
                        ),
                        const SizedBox(height: 7),
                        const Divider(height: 1, color: AppColors.divider),
                        const SizedBox(height: 10),
                        Text(
                          data.summary,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BindingChip extends StatelessWidget {
  const _BindingChip({required this.bound});

  final bool bound;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: AppRadius.full,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              bound
                  ? Icons.check_circle_outline_rounded
                  : Icons.add_circle_outline,
              color: AppColors.brandPrimary,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              bound ? '当前绑定' : '待绑定',
              style: const TextStyle(
                color: AppColors.brandPrimary,
                fontSize: 12,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentMetric extends StatelessWidget {
  const _EnvironmentMetric({
    required this.assetPath,
    required this.label,
    this.value,
    this.rating,
    this.warning = false,
  });

  final String assetPath;
  final String label;
  final String? value;
  final int? rating;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Image.asset(
          assetPath,
          width: 36,
          height: 36,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: label,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
              if (rating != null)
                _RatingStars(
                  rating: rating!,
                  color: AppColors.warning,
                  size: 15,
                )
              else
                Text(
                  value ?? '',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlantBasicInfoCard extends StatelessWidget {
  const _PlantBasicInfoCard({required this.plant, required this.data});

  final PlantProfile plant;
  final _PlantDetailData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SectionHeader(
              assetPath: AppAssets.selectPlantIcon,
              title: '基础信息',
            ),
            const SizedBox(height: 14),
            _DetailRow(label: '学名', child: Text(plant.latinName)),
            const SizedBox(height: 12),
            _DetailRow(label: '别名', child: Text(data.alias)),
            const SizedBox(height: 12),
            _DetailRow(
              label: '养护难度',
              child: _RatingStars(
                rating: data.difficulty,
                color: AppColors.brandPrimary,
                size: 16,
              ),
            ),
            const SizedBox(height: 12),
            _DetailRow(label: '浇水频率', child: Text(data.watering)),
            const SizedBox(height: 12),
            _DetailRow(label: '生长特点', child: Text(data.growth)),
            if (data.lightingSuggestion.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _DetailRow(label: '光照建议', child: Text(data.lightingSuggestion)),
            ],
            if (data.waterSuggestion.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _DetailRow(label: '需水建议', child: Text(data.waterSuggestion)),
            ],
            if (data.temperatureSuggestion.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _DetailRow(
                label: '空气温度建议',
                child: Text(data.temperatureSuggestion),
              ),
            ],
            if (data.humiditySuggestion.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _DetailRow(label: '湿度建议', child: Text(data.humiditySuggestion)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
        Expanded(
          child: DefaultTextStyle(
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              height: 1.45,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _PlantCareAdviceCard extends StatelessWidget {
  const _PlantCareAdviceCard({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SectionHeader(
              assetPath: AppAssets.plantCareTipIcon,
              title: '养护建议',
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < items.length; index++) ...<Widget>[
              _AdviceBullet(text: items[index]),
              if (index != items.length - 1) const SizedBox(height: 5),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.assetPath, required this.title});

  final String assetPath;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Image.asset(
          assetPath,
          width: 23,
          height: 23,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: title,
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _AdviceBullet extends StatelessWidget {
  const _AdviceBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 10,
              child: Center(
                child: SizedBox.square(
                  dimension: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingStars extends StatelessWidget {
  const _RatingStars({
    required this.rating,
    required this.color,
    required this.size,
  });

  final int rating;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(
        5,
        (index) => Icon(
          index < rating ? Icons.star : Icons.star_outline,
          color: color,
          size: size,
        ),
      ),
    );
  }
}

class _PlantDetailArtwork extends StatelessWidget {
  const _PlantDetailArtwork({required this.plant, super.key});

  final PlantProfile plant;

  @override
  Widget build(BuildContext context) {
    final imageUrl = plant.imageUrl?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: plant.name,
        errorBuilder: (_, _, _) => Image.asset(
          AppAssets.plantImage(plant.id),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
    }
    return Image.asset(
      AppAssets.plantImage(plant.id),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: plant.name,
    );
  }
}

class _PlantDetailData {
  const _PlantDetailData({
    required this.temperature,
    required this.humidity,
    required this.lightRating,
    required this.summary,
    required this.alias,
    required this.difficulty,
    required this.watering,
    required this.growth,
    required this.careAdvice,
    this.lightingSuggestion = '',
    this.waterSuggestion = '',
    this.temperatureSuggestion = '',
    this.humiditySuggestion = '',
  });

  final String temperature;
  final String humidity;
  final int lightRating;
  final String summary;
  final String alias;
  final int difficulty;
  final String watering;
  final String growth;
  final List<String> careAdvice;

  /// 后台单独维护的四条建议文案。**没有本地兜底**：写死的 `_byId` / `_generic`
  /// 里都是空串，后台没配就整行不显示，不拿阈值区间冒充建议。
  final String lightingSuggestion;
  final String waterSuggestion;
  final String temperatureSuggestion;
  final String humiditySuggestion;

  /// Written per plant. The generic fallback produced near-identical cards —
  /// same temperature range, same three tips, and `别名` echoing the plant's
  /// own name — so every plant read the same in the picker.
  factory _PlantDetailData.fromProfile(PlantProfile plant) {
    final fallback = _byId[plant.id] ?? _generic(plant);
    final hasBackendDetail =
        plant.introduction.isNotEmpty ||
        plant.alias.isNotEmpty ||
        plant.temperatureRequirement.isNotEmpty ||
        plant.humidityRequirement.isNotEmpty ||
        plant.lightingRequirement.isNotEmpty ||
        plant.wateringFrequency.isNotEmpty ||
        plant.growthCharacteristics.isNotEmpty ||
        plant.careInstructions.isNotEmpty ||
        plant.lightingSuggestion.isNotEmpty ||
        plant.waterSuggestion.isNotEmpty ||
        plant.temperatureSuggestion.isNotEmpty ||
        plant.humiditySuggestion.isNotEmpty ||
        plant.difficultyMaintenance != null;
    if (!hasBackendDetail) return fallback;
    final careAdvice = plant.careInstructions
        .split(RegExp(r'[\r\n；;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return _PlantDetailData(
      temperature: plant.temperatureRequirement.isEmpty
          ? fallback.temperature
          : plant.temperatureRequirement,
      humidity: plant.humidityRequirement.isEmpty
          ? fallback.humidity
          : plant.humidityRequirement,
      lightRating: _rating(plant.lightingRequirement, fallback.lightRating),
      summary: plant.introduction.isEmpty
          ? fallback.summary
          : plant.introduction,
      alias: plant.alias.isEmpty ? fallback.alias : plant.alias,
      difficulty: (plant.difficultyMaintenance ?? fallback.difficulty)
          .clamp(1, 5)
          .toInt(),
      watering: plant.wateringFrequency.isEmpty
          ? fallback.watering
          : plant.wateringFrequency,
      growth: plant.growthCharacteristics.isEmpty
          ? fallback.growth
          : plant.growthCharacteristics,
      careAdvice: careAdvice.isEmpty ? fallback.careAdvice : careAdvice,
      lightingSuggestion: plant.lightingSuggestion,
      waterSuggestion: plant.waterSuggestion,
      temperatureSuggestion: plant.temperatureSuggestion,
      humiditySuggestion: plant.humiditySuggestion,
    );
  }

  static int _rating(String value, int fallback) {
    final match = RegExp(r'[1-5]').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? fallback;
  }

  static const _byId = <String, _PlantDetailData>{
    'pilea_cadierei': pilea,
    'pothos': pothos,
    'ivy': ivy,
    'monstera': monstera,
    'bird_of_paradise': birdOfParadise,
    'china_doll': chinaDoll,
  };

  static _PlantDetailData _generic(PlantProfile plant) {
    final highMoisture = plant.moistureTarget >= 60;
    final highLight = plant.lightTarget >= 220;
    return _PlantDetailData(
      temperature: '18-28°C',
      humidity: highMoisture ? '55-75%' : '45-65%',
      lightRating: highLight ? 4 : 3,
      summary: plant.tip,
      alias: plant.latinName,
      difficulty: 3,
      watering: highMoisture ? '生长期每周2-3次，冬季适当减少' : '表土干燥后浇透，避免盆内积水',
      growth: '适合室内明亮散射光环境，保持良好通风可促进健康生长。',
      careAdvice: <String>[
        '避免阳光直射，放在明亮的散射光处。',
        '根据土壤干湿情况补水，避免长期积水。',
        '生长期定期补充稀释肥料，及时清理枯叶。',
      ],
    );
  }

  static const pothos = _PlantDetailData(
    temperature: '15-30°C',
    humidity: '50-70%',
    lightRating: 2,
    summary: '藤蔓下垂生长，叶片心形油亮，耐阴好养，是最适合新手的室内绿植之一。',
    alias: '黄金葛',
    difficulty: 1,
    watering: '春夏每周1-2次，冬季10-15天一次，宁干勿涝',
    growth: '生长速度快，可水培也可土培，攀爬或垂吊都有观赏性，耐阴性极强。',
    careAdvice: <String>[
      '放在有散射光的位置即可，长期全黑会让叶片斑纹变淡。',
      '盆土表面干透再浇，冬季减少浇水，避免烂根。',
      '藤蔓过长时随时修剪，剪下的枝条插水里就能生根。',
    ],
  );

  static const ivy = _PlantDetailData(
    temperature: '10-25°C',
    humidity: '55-75%',
    lightRating: 3,
    summary: '枝叶纤细成串垂落，耐寒耐阴，适合放在书架或窗台边营造层次感。',
    alias: '洋常春藤',
    difficulty: 2,
    watering: '春秋每周1-2次，夏季保持土壤微润，冬季控水',
    growth: '喜凉爽湿润，怕闷热，通风不良时容易生红蜘蛛，夏季需注意降温。',
    careAdvice: <String>[
      '避开正午直射光，明亮散射光下叶色最好。',
      '天气干燥时向叶片喷水，既增湿也能减少虫害。',
      '每年春季换盆一次，同时修剪过密的枝条。',
    ],
  );

  static const monstera = _PlantDetailData(
    temperature: '18-30°C',
    humidity: '55-75%',
    lightRating: 3,
    summary: '叶片宽大并自然开裂，造型感强，是室内最上镜的观叶植物之一。',
    alias: '蓬莱蕉',
    difficulty: 2,
    watering: '春夏每周1次浇透，冬季2周1次，表土干2-3厘米再浇',
    growth: '生长期长得快，叶片会随成熟度增加裂口，成株需要支撑柱引导攀爬。',
    careAdvice: <String>[
      '明亮散射光处开裂最漂亮，光照太弱新叶会不开裂。',
      '定期用湿布擦拭叶面，保持光泽也利于呼吸。',
      '气生根不要剪掉，可以引导入土帮助吸收养分。',
    ],
  );

  static const birdOfParadise = _PlantDetailData(
    temperature: '18-30°C',
    humidity: '45-65%',
    lightRating: 5,
    summary: '叶片挺拔如扇，株型大气，光照充足时可开出形似飞鸟的橙蓝色花朵。',
    alias: '鹤望兰',
    difficulty: 3,
    watering: '生长期每周1-2次浇透，冬季减半，忌盆内积水',
    growth: '喜光耐旱，光照越足株型越紧凑；室内养护建议放在南向窗边。',
    careAdvice: <String>[
      '每天至少4小时明亮光照，长期光照不足很难开花。',
      '叶片易被风吹裂属正常现象，不影响健康。',
      '生长期每月补一次磷钾肥，有助于孕蕾。',
    ],
  );

  static const chinaDoll = _PlantDetailData(
    temperature: '18-28°C',
    humidity: '50-70%',
    lightRating: 4,
    summary: '羽状复叶层层展开，新叶嫩绿明快，寓意好，常作为乔迁与开业的礼物。',
    alias: '菜豆树',
    difficulty: 3,
    watering: '春夏每周2次，秋冬每周1次，保持土壤微润',
    growth: '喜温暖湿润和充足散射光，环境突变时容易落叶，缓苗后会重新萌发。',
    careAdvice: <String>[
      '刚搬回家掉叶属于正常缓苗，先固定位置不要频繁挪动。',
      '空气干燥时向周围喷雾，避免叶尖发黄干枯。',
      '每年春季修剪徒长枝，保持树形紧凑。',
    ],
  );

  static const pilea = _PlantDetailData(
    temperature: '18-28°C',
    humidity: '50-70%',
    lightRating: 3,
    summary: '叶片布满银白色脉纹，清新雅致，喜湿润明亮环境，适合室内桌面或半阴环境栽培。',
    alias: '银脉冷水花',
    difficulty: 3,
    watering: '春秋每周1-2次，夏季每周2-3次，冬季每周1次',
    growth: '喜湿润环境，生长迅速，耐阴性较强，叶色清新，极具观赏价值。',
    careAdvice: <String>[
      '避免阳光直射，放在明亮的散射光处，如窗边或室内明亮处。',
      '保持土壤湿润但不积水，空气干燥时可向叶片喷水增湿。',
      '生长期每月施一次稀释的液体肥，促进叶片生长更旺盛。',
    ],
  );
}
