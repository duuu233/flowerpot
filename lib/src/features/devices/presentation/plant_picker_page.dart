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
    selectedId = current?.id ?? PlantCatalog.items.first.id;
    initialized = true;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<PlantProfile> get visiblePlants {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return PlantCatalog.items;
    return PlantCatalog.items
        .where(
          (item) =>
              item.name.contains(keyword) ||
              item.latinName.toLowerCase().contains(keyword),
        )
        .toList();
  }

  PlantProfile get selected => PlantCatalog.items.firstWhere(
    (item) => item.id == selectedId,
    orElse: () => PlantCatalog.items.first,
  );

  Future<void> _confirmSelection() async {
    final result = await FlowerpotScope.of(
      context,
    ).selectPlant(widget.deviceId, selected);
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageMargin,
                    28,
                    AppSpacing.pageMargin,
                    0,
                  ),
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageMargin,
                    0,
                    AppSpacing.pageMargin,
                    112,
                  ),
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
                        key: Key('plant-card-${plant.id}'),
                        plant: plant,
                        selected: selectedId == plant.id,
                        onTap: () =>
                            setState(() => selectedId = plant.id),
                        onDetails: () => Navigator.pushNamed(
                          context,
                          AppRoutes.plantDetail,
                          arguments: PlantDetailArguments(
                            plant: plant,
                            bound:
                                state.deviceById(widget.deviceId)?.plant.id ==
                                plant.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          Positioned(
            left: AppSpacing.pageMargin,
            right: AppSpacing.pageMargin,
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
    // The design seats the bulb on a white disc.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 36,
        child: Center(
          child: Image.asset(
            AppAssets.plantCareTipIcon,
            width: 22,
            height: 22,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: '植物选择提示',
          ),
        ),
      ),
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

  final PlantProfile plant;
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
                  child: Padding(
                    // The artwork ranges from 146x172 to 388x368, so it is
                    // contained rather than cropped to keep the grid even.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Image.asset(
                      AppAssets.plantImage(plant.id),
                      key: Key('plant-image-${plant.id}'),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      semanticLabel: plant.name,
                    ),
                  ),
                ),
                if (selected)
                  Material(
                    color: AppColors.brandPrimary,
                    child: InkWell(
                      key: Key('plant-details-${plant.id}'),
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
                        plant.name,
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
    // The design's mark is a white tick on a solid brand disc. There is no
    // such asset, so the disc is a plain coloured circle carrying the existing
    // tick artwork rather than a redrawn icon.
    return Semantics(
      label: '已选择',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.brandPrimary,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 23,
          child: Center(
            child: Image.asset(
              AppAssets.checkmarkIcon,
              width: 13,
              height: 13,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              color: AppColors.surface,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
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

