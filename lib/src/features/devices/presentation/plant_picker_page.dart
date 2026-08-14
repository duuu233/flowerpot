import 'package:flutter/material.dart';

import '../../../app/flowerpot_app.dart';
import '../../../design_system/design_system.dart';
import '../../../routes/app_routes.dart';
import '../../../tuya/tuya_models.dart';
import '../../home/models/home_dashboard_model.dart';
import '../../home/presentation/home_page.dart';
import 'plant_detail_page.dart';

enum PlantPickerMode { add, select }

class PlantPickerArguments {
  const PlantPickerArguments({required this.deviceId, required this.mode});

  final String deviceId;
  final PlantPickerMode mode;
}

class PlantPickerPage extends StatefulWidget {
  const PlantPickerPage({required this.deviceId, super.key, this.mode});

  final String deviceId;
  final PlantPickerMode? mode;

  @override
  State<PlantPickerPage> createState() => _PlantPickerPageState();
}

class _PlantPickerPageState extends State<PlantPickerPage> {
  final searchController = TextEditingController();
  String query = '';
  String? selectedId;
  bool initialized = false;
  bool addingPlant = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    final state = FlowerpotScope.of(context);
    final planted = state.hasPlant(widget.deviceId);
    addingPlant = widget.mode != null
        ? widget.mode == PlantPickerMode.add
        : !planted;
    final current = planted ? state.deviceById(widget.deviceId)?.plant : null;
    selectedId = current?.id ?? _plants.first.profile.id;
    initialized = true;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<_PlantChoice> get visiblePlants {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return _plants;
    return _plants
        .where(
          (item) =>
              item.profile.name.contains(keyword) ||
              item.profile.latinName.toLowerCase().contains(keyword),
        )
        .toList();
  }

  _PlantChoice get selected => _plants.firstWhere(
    (item) => item.profile.id == selectedId,
    orElse: () => _plants.first,
  );

  Future<void> _confirmSelection() async {
    final result = await FlowerpotScope.of(
      context,
    ).selectPlant(widget.deviceId, selected.profile);
    if (!mounted) return;
    showAppMessage(
      context,
      result.message,
      tone: result.success ? AppMessageTone.success : AppMessageTone.error,
    );
    if (result.success) {
      if (addingPlant) {
        // Replace the "no plant yet" page with the device detail page, so
        // going back from here returns to the device list.
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.deviceHome,
          (route) => route.isFirst || route.settings.name == AppRoutes.shell,
          arguments: HomeDeviceArguments(
            deviceId: widget.deviceId,
            scene: HomeDashboardScene.withCompanionSummary,
          ),
        );
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final plants = visiblePlants;
    return AppPageScaffold(
      appBar: AppPageHeader(
        title: addingPlant ? '添加植物' : '选择植物',
        leading: const AppBackButton(),
      ),
      background: AppPageBackground.standard,
      body: Stack(
        children: <Widget>[
          CustomScrollView(
            key: const Key('plant-picker-scroll-view'),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: ResponsiveContent(
                  maxWidth: 375,
                  padding: const EdgeInsets.fromLTRB(20, 80, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _PlantSearchField(
                        controller: searchController,
                        onChanged: (value) => setState(() => query = value),
                      ),
                      const SizedBox(height: 12),
                      const _PlantTipCard(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (plants.isEmpty)
                const SliverToBoxAdapter(child: _EmptySearchResult())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 112),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 152,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: plants.length,
                    itemBuilder: (context, index) {
                      final plant = plants[index];
                      return _PlantCard(
                        key: Key('plant-card-${plant.profile.id}'),
                        plant: plant,
                        selected: selectedId == plant.profile.id,
                        onTap: () =>
                            setState(() => selectedId = plant.profile.id),
                        onDetails: () => Navigator.pushNamed(
                          context,
                          AppRoutes.plantDetail,
                          arguments: PlantDetailArguments(
                            plant: plant.profile,
                            bound:
                                state.deviceById(widget.deviceId)?.plant.id ==
                                plant.profile.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 8,
            child: FilledButton(
              key: const Key('confirm-plant-selection'),
              onPressed: state.busy ? null : _confirmSelection,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: AppColors.surface,
                elevation: 2,
                shadowColor: AppColors.brandPrimary.withValues(alpha: .35),
                shape: const StadiumBorder(),
                textStyle: AppTypography.pageTitle.copyWith(
                  color: AppColors.surface,
                ),
              ),
              child: state.busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.surface,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(addingPlant ? '确认添加' : '确认选择'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlantSearchField extends StatelessWidget {
  const _PlantSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TextField(
        key: const Key('plant-search-field'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: AppTypography.body,
        decoration: InputDecoration(
          hintText: '搜索植物名称',
          hintStyle: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
            fontSize: 15,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(11),
            child: Image.asset(
              AppAssets.searchIcon,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: const OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: AppRadius.full,
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: AppRadius.full,
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.brandPrimary),
            borderRadius: AppRadius.full,
          ),
        ),
      ),
    );
  }
}

class _PlantTipCard extends StatelessWidget {
  const _PlantTipCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _TipIcon(),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '选择植物，获取更精准的养护建议',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  Text(
                    '我们将根据植物类型，为您提供个性化的光照、浇水、施肥等养护指导。',
                    style: TextStyle(
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
      ),
    );
  }
}

class _TipIcon extends StatelessWidget {
  const _TipIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.plantCareTipIcon,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '植物选择提示',
    );
  }
}

class _PlantCard extends StatelessWidget {
  const _PlantCard({
    required this.plant,
    required this.selected,
    required this.onTap,
    required this.onDetails,
    super.key,
  });

  final _PlantChoice plant;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: selected
            ? const BorderSide(color: AppColors.brandPrimary, width: 1.5)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: ColoredBox(
                    key: Key('plant-image-placeholder-${plant.profile.id}'),
                    color: plant.profile.color.withValues(alpha: .14),
                  ),
                ),
                if (selected)
                  Material(
                    color: AppColors.brandPrimary,
                    child: InkWell(
                      key: Key('plant-details-${plant.profile.id}'),
                      onTap: onDetails,
                      child: const SizedBox(
                        height: 28,
                        child: Center(
                          child: Text(
                            '查看详情',
                            style: TextStyle(
                              color: AppColors.surface,
                              fontSize: 15,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 35,
                    child: Center(
                      child: Text(
                        plant.profile.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (selected)
              const Positioned(top: 11, right: 11, child: _SelectedBadge()),
          ],
        ),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.plantSelectionBadgeIcon,
      width: 23,
      height: 23,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '已选择',
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: Text(
          '没有找到相关植物',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ),
    );
  }
}

class _PlantChoice {
  const _PlantChoice({required this.profile});

  final PlantProfile profile;
}

const _plants = <_PlantChoice>[
  _PlantChoice(
    profile: PlantProfile(
      id: 'pilea_cadierei',
      name: '冷水花',
      latinName: 'Pilea cadierei',
      color: Color(0xFF4D8B55),
      moistureTarget: 68,
      lightTarget: 120,
      tip: '喜湿润明亮环境，适合室内桌面或半阴环境栽培。',
    ),
  ),
  _PlantChoice(
    profile: PlantProfile(
      id: 'pothos',
      name: '绿萝',
      latinName: 'Epipremnum aureum',
      color: Color(0xFF65A765),
      moistureTarget: 62,
      lightTarget: 100,
      tip: '耐阴但不耐积水，保持通风有助于新叶生长。',
    ),
  ),
  _PlantChoice(
    profile: PlantProfile(
      id: 'ivy',
      name: '常春藤',
      latinName: 'Hedera helix',
      color: Color(0xFF527B48),
      moistureTarget: 58,
      lightTarget: 150,
      tip: '适合明亮散射光，保持盆土微润并注意通风。',
    ),
  ),
  _PlantChoice(
    profile: PlantProfile(
      id: 'monstera',
      name: '龟背竹',
      latinName: 'Monstera deliciosa',
      color: Color(0xFF2F7D5D),
      moistureTarget: 58,
      lightTarget: 140,
      tip: '喜欢明亮散射光，表层土壤微干后再浇水。',
    ),
  ),
  _PlantChoice(
    profile: PlantProfile(
      id: 'bird_of_paradise',
      name: '天堂鸟',
      latinName: 'Strelitzia reginae',
      color: Color(0xFF4F8C54),
      moistureTarget: 55,
      lightTarget: 260,
      tip: '需要充足的柔和光照，生长期保持土壤均匀湿润。',
    ),
  ),
  _PlantChoice(
    profile: PlantProfile(
      id: 'china_doll',
      name: '幸福树',
      latinName: 'Radermachera sinica',
      color: Color(0xFF367C46),
      moistureTarget: 60,
      lightTarget: 180,
      tip: '喜温暖明亮环境，避免积水和长时间强光直射。',
    ),
  ),
  _PlantChoice(
    profile: PlantProfile(
      id: 'pepperomia',
      name: '豆瓣绿',
      latinName: 'Peperomia tetraphylla',
      color: Color(0xFF5E9664),
      moistureTarget: 50,
      lightTarget: 130,
      tip: '保持明亮散射光，等表层土壤干燥后再补水。',
    ),
  ),
  _PlantChoice(
    profile: PlantProfile(
      id: 'philodendron',
      name: '春羽',
      latinName: 'Philodendron selloum',
      color: Color(0xFF36765A),
      moistureTarget: 60,
      lightTarget: 150,
      tip: '适合温暖湿润的散射光环境，注意避免低温。',
    ),
  ),
];
