import 'package:flutter/material.dart';

import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';

class PlantDetailArguments {
  const PlantDetailArguments({required this.plant, this.bound = false});

  final PlantProfile plant;
  final bool bound;
}

class PlantDetailPage extends StatelessWidget {
  const PlantDetailPage({required this.arguments, super.key});

  final PlantDetailArguments arguments;

  @override
  Widget build(BuildContext context) {
    final data = _PlantDetailData.fromProfile(arguments.plant);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '植物详情', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: SingleChildScrollView(
        key: const Key('plant-detail-scroll-view'),
        child: ResponsiveContent(
          maxWidth: 375,
          padding: const EdgeInsets.fromLTRB(20, 88, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const MockDataBanner(
                title: '示例养护数据',
                message: '适宜温湿度、光照需求、难度、浇水频率与养护建议都是按阈值推导的'
                    '占位内容，不是植物库数据。',
              ),
              _PlantSummaryCard(
                plant: arguments.plant,
                data: data,
                bound: arguments.bound,
              ),
              const SizedBox(height: 12),
              _PlantBasicInfoCard(plant: arguments.plant, data: data),
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
                          child: ColoredBox(
                            key: const Key('plant-detail-image-placeholder'),
                            color: plant.color.withValues(alpha: .14),
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
          index < rating ? Icons.star_rounded : Icons.star_outline_rounded,
          color: color,
          size: size,
        ),
      ),
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

  factory _PlantDetailData.fromProfile(PlantProfile plant) {
    if (plant.id == 'pilea_cadierei') return pilea;
    final highMoisture = plant.moistureTarget >= 60;
    final highLight = plant.lightTarget >= 220;
    return _PlantDetailData(
      temperature: '18-28°C',
      humidity: highMoisture ? '55-75%' : '45-65%',
      lightRating: highLight ? 4 : 3,
      summary: plant.tip,
      alias: plant.name,
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
