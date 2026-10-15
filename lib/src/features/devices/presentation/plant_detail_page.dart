import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/config/debug_log_gate.dart';

import '../../../app/flowerpot_app.dart';
import '../../../app/network_alert.dart';
import '../../../design_system/design_system.dart';
import '../../../tuya/tuya_models.dart';

class PlantDetailArguments {
  const PlantDetailArguments({
    required this.plant,
    this.bound = false,
    this.selectable = false,
    this.addingPlant = false,
  });

  final PlantProfile plant;
  final bool bound;

  /// 从「选择植物」页进来的：详情页底部也要画一个确认按钮
  /// （2026-09-12 产品：「选择植物下面的确认选择按钮，在植物详情也需要」）。
  ///
  /// ⚠️ 按钮**自己不下发**，只是带着「用户选了这株」的结果 `pop` 回选择植物页，
  /// 由那一页统一执行 `selectPlant` 和随后的跳转。选择流程只有一份实现，两个入口
  /// 的行为就不会分叉。
  final bool selectable;

  /// 只影响按钮文案：添加植物时是「确认添加」，更换时是「确认选择」。
  final bool addingPlant;
}

/// 详情页。
///
/// ⚠️ **进页面必须单独拉一次植物详情**（2026-09-12 按 swagger 核实后改）。
///
/// 此前这里写着「`getProductPlantList` 已经把字段带齐了，不再单独打详情接口」——
/// **那个假设是错的**：列表的返回体 `ClientProductPlantApiOut` 只有五个字段
/// （`productPlantId` / `plantName` / `plantImg` / `tuYaRemark` / `categoryType`），
/// **学名、别名、简介、温湿度、养护建议一个都没有**。所以这一页的「学名」「别名」
/// 一直是空的——产品反馈的正是这个。全套在
/// `/Client/UserProduct/getUserProductPlantDetail`（id 传 productPlantId）里。
///
/// 先用列表那份画（名字和图片已经够画首屏），详情回来再补齐；拉不到就保持空白，
/// **不拿本地数据顶替**。
class PlantDetailPage extends StatefulWidget {
  const PlantDetailPage({required this.arguments, super.key});

  final PlantDetailArguments arguments;

  @override
  State<PlantDetailPage> createState() => _PlantDetailPageState();
}

class _PlantDetailPageState extends State<PlantDetailPage>
    with NetworkRetryAware<PlantDetailPage> {
  PlantProfile? _detail;
  bool _loading = false;
  bool _requested = false;

  PlantProfile get plant => _detail ?? widget.arguments.plant;

  PlantDetailArguments get arguments => widget.arguments;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    unawaited(_loadDetail());
  }

  /// 「网络异常」弹窗点「重试」：按进页面时的参数再拉一次详情。
  @override
  Future<void> reloadForNetworkRetry() => _loadDetail();

  Future<void> _loadDetail() async {
    // 2026-09-12 接口加了 `tuYaRemark`，和原来的 `id` 二选一。**优先涂鸦标识**：
    // 它是 DP 116 报上来的那个值，后台也保证不重复；自增 id 只做兜底。
    final source = widget.arguments.plant;
    final remark = source.tuyaIdentifier.trim();
    final id = source.productPlantId;
    if (remark.isEmpty && id == null) return;
    setState(() => _loading = true);
    final value = await FlowerpotScope.of(context).loadPlantDetail(
      productPlantId: id,
      tuyaRemark: remark.isEmpty ? null : remark,
    );
    if (!mounted) return;
    setState(() {
      if (value != null) _detail = value;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _PlantDetailData.fromProfile(plant);
    return AppPageScaffold(
      appBar: const AppPageHeader(title: '植物详情', leading: AppBackButton()),
      background: AppPageBackground.standard,
      body: Stack(
        children: <Widget>[
          SingleChildScrollView(
            key: const Key('plant-detail-scroll-view'),
            child: ResponsiveContent(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                23,
                AppSpacing.pageMargin,
                // 有确认按钮时给它让出位置，免得最后一张卡被压在按钮底下。
                arguments.selectable ? 96 : 28,
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
                  _PlantBasicInfoCard(
                    plant: plant,
                    data: data,
                    detailLoading: _loading,
                    detailLoaded: _detail != null,
                  ),
                  const SizedBox(height: 12),
                  _PlantCareAdviceCard(items: data.careAdvice),
                ],
              ),
            ),
          ),
          if (arguments.selectable)
            Positioned(
              left: AppSpacing.pageMargin,
              right: AppSpacing.pageMargin,
              bottom: 8,
              child: _ConfirmPlantButton(addingPlant: arguments.addingPlant),
            ),
        ],
      ),
    );
  }
}

/// 详情页底部的「确认选择 / 确认添加」，样式照搬选择植物页那一颗。
///
/// ⚠️ **它不下发任何东西**，只是 `pop(true)` 回选择植物页，由那一页执行
/// `selectPlant` 和随后的跳转——选择流程只有一份实现，两个入口不会走岔。
class _ConfirmPlantButton extends StatelessWidget {
  const _ConfirmPlantButton({required this.addingPlant});

  final bool addingPlant;

  @override
  Widget build(BuildContext context) {
    final busy = FlowerpotScope.of(context).busy;
    return FilledButton(
      key: const Key('confirm-plant-from-detail'),
      onPressed: busy ? null : () => Navigator.pop(context, true),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: AppColors.brandPrimary,
        foregroundColor: AppColors.surface,
        elevation: 2,
        shadowColor: AppColors.brandPrimary.withValues(alpha: .35),
        shape: const StadiumBorder(),
        textStyle: AppTypography.pageTitle.copyWith(color: AppColors.surface),
      ),
      child: Text(addingPlant ? '确认添加' : '确认选择'),
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
                  // 稿子 156:5869：右列从卡内 y≈30 起、指标行距 48（原 16 起、43），
                  // 右列挤在上半、分隔线高了 29。
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: 14),
                        _EnvironmentMetric(
                          assetPath: AppAssets.metricTemperatureIcon,
                          label: '适宜温度',
                          value: data.temperature,
                        ),
                        const SizedBox(height: 12),
                        _EnvironmentMetric(
                          assetPath: AppAssets.statusHumidityIcon,
                          label: '适宜湿度',
                          value: data.humidity,
                        ),
                        const SizedBox(height: 12),
                        _EnvironmentMetric(
                          assetPath: AppAssets.metricLightIcon,
                          label: '光照需求',
                          rating: data.lightRating,
                          warning: true,
                        ),
                        const SizedBox(height: 7),
                        const Divider(height: 1, color: AppColors.divider),
                        const SizedBox(height: 10),
                        // 卡片是定高的：简介放得下几行就画几行，多出来的收成省略号，
                        // 不让右列溢出（上面按稿子加了间距之后余量更小了）。
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) => Text(
                              data.summary,
                              maxLines: (box.maxHeight / (12 * 1.45))
                                  .floor()
                                  .clamp(1, 20)
                                  .toInt(),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
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
  const _PlantBasicInfoCard({
    required this.plant,
    required this.data,
    required this.detailLoading,
    required this.detailLoaded,
  });

  final PlantProfile plant;
  final _PlantDetailData data;

  /// 详情接口还在路上。只画在 debug 包的「接口体检」行里用。
  final bool detailLoading;

  /// 详情接口已经取回了数据。同上，只给体检行用。
  final bool detailLoaded;

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
            // 空值显式画一句，别留一行空白——分不清是"后台没配"还是"App 没读到"。
            _DetailRow(
              label: '学名',
              child: Text(
                plant.latinName.trim().isEmpty ? '--' : plant.latinName,
              ),
            ),
            const SizedBox(height: 12),
            _DetailRow(
              label: '别名',
              child: Text(data.alias.trim().isEmpty ? '--' : data.alias),
            ),
            // ⚠️ **只在 debug 包出现的字段体检**（2026-09-11）。
            //
            // 产品反馈「详情页没读到图片、学名、别名」，而后台那条数据（tuYaRemark=17）
            // 明明配全了。差别在于：**详情页用的是列表接口 `getProductPlantList` 传进来的
            // 对象，从不单独拉详情**——列表返回什么，这一页就只有什么。所以要能一眼看出
            // 到底是哪几项没从接口下来。正式包不画。
            if (DebugLogGate.enabled && kDebugMode) ...<Widget>[
              const SizedBox(height: 12),
              _DetailRow(
                label: '接口体检',
                child: Text(
                  <String>[
                    '图片 ${(plant.imageUrl ?? '').trim().isEmpty ? '空' : '有'}',
                    '学名 ${plant.latinName.trim().isEmpty ? '空' : '有'}',
                    '别名 ${data.alias.trim().isEmpty ? '空' : '有'}',
                    '涂鸦标识 ${plant.tuyaIdentifier.trim().isEmpty ? '空' : plant.tuyaIdentifier}',
                    detailLoading
                        ? '详情接口 加载中'
                        : '详情接口 ${detailLoaded ? '已取到' : '未取到'}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
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

/// 详情页那株植物的图，只认后端配的 `plantImg`。
///
/// ⚠️ **没有就留空**（2026-09-12 产品口径：「去掉一切兜底、静态假数据，没有就为空」）。
/// 这里原来会回落到 `AppAssets.plantImage(plant.id)` ——一张按 id 查本地图片表的静态图。
/// 后台配的植物 id 根本不在那张表里，查不到还会再退成一个通用图标，等于**给每一株
/// 认不出来的植物都画上同一张图**，看着像数据齐了，其实什么都没有。
///
/// 背后的浅色圆底还在（画在外层 Stack 里），所以留空不会塌成一条缝。
class _PlantDetailArtwork extends StatelessWidget {
  const _PlantDetailArtwork({required this.plant, super.key});

  final PlantProfile plant;

  @override
  Widget build(BuildContext context) {
    final imageUrl = plant.imageUrl?.trim();
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
    return Image.network(
      imageUrl,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: plant.name,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
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

  /// 后台单独维护的四条建议文案。后台没配就整行不显示，不拿阈值区间冒充建议。
  final String lightingSuggestion;
  final String waterSuggestion;
  final String temperatureSuggestion;
  final String humiditySuggestion;

  /// Written per plant. The generic fallback produced near-identical cards —
  /// same temperature range, same three tips, and `别名` echoing the plant's
  /// own name — so every plant read the same in the picker.
  /// 从后端植物资料构造。**一律用真实数据，后端没给就留空。**
  ///
  /// ⚠️ 2026-09-12 产品口径：「去掉静态数据，所有都要真实的数据，没有就为空」。
  ///
  /// 改之前这里有一整套**本地写死的兜底**（`_byId` 按 id 配了六种植物、`_generic` 按
  /// 含水量/光照阈值现编一份），任何一个字段后端为空就拿兜底顶上。结果是页面上显示着
  /// 一份**看起来有、实际是编的**植物资料——产品说的「页面数据都是错的」就是它。
  /// 空着反而是对的：一眼能看出后台哪几项没配。
  factory _PlantDetailData.fromProfile(PlantProfile plant) {
    final careAdvice = plant.careInstructions
        .split(RegExp(r'[\r\n；;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return _PlantDetailData(
      temperature: plant.temperatureRequirement,
      humidity: plant.humidityRequirement,
      // 后端给的是枚举数字 + `…Msg` 人话（见 `app_backend_repository._plant`）。
      // 解析不出 1..5 就给 0——由页面决定这一行画不画，不再猜一个 3 出来。
      lightRating: _rating(plant.lightingRequirement),
      summary: plant.introduction,
      alias: plant.alias,
      // 后端没给难度就是 0：星级那一行按 0 处理，不再默认 3 星。
      difficulty: (plant.difficultyMaintenance ?? 0).clamp(0, 5).toInt(),
      watering: plant.wateringFrequency,
      growth: plant.growthCharacteristics,
      careAdvice: careAdvice,
      lightingSuggestion: plant.lightingSuggestion,
      waterSuggestion: plant.waterSuggestion,
      temperatureSuggestion: plant.temperatureSuggestion,
      humiditySuggestion: plant.humiditySuggestion,
    );
  }

  /// 从光照要求里取 1..5 的星级；取不到给 0（= 没有数据，不画星）。
  static int _rating(String value) {
    final match = RegExp(r'[1-5]').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }
}
