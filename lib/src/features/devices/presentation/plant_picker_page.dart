import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/flowerpot_app.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../tuya/tuya_models.dart';

class PlantPickerPage extends StatefulWidget {
  const PlantPickerPage({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<PlantPickerPage> createState() => _PlantPickerPageState();
}

class _PlantPickerPageState extends State<PlantPickerPage> {
  PlantProfile? selected;

  @override
  Widget build(BuildContext context) {
    final state = FlowerpotScope.of(context);
    final current = state.deviceById(widget.deviceId)?.plant;
    selected ??= current ?? PlantCatalog.items.first;
    return Scaffold(
      appBar: AppBar(title: const Text('选择植物')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: .78,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: PlantCatalog.items.length,
                  itemBuilder: (context, index) {
                    final plant = PlantCatalog.items[index];
                    final active = selected?.id == plant.id;
                    return GlassCard(
                      onTap: () => setState(() => selected = plant),
                      color: active ? plant.color.withValues(alpha: .16) : null,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: <Widget>[
                          Align(
                            alignment: Alignment.topRight,
                            child: Icon(
                              active
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: active ? AppColors.leaf : AppColors.muted,
                            ),
                          ),
                          Expanded(
                            child: PlantIllustration(
                              size: 112,
                              leafColor: plant.color,
                            ),
                          ),
                          Text(
                            plant.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            plant.latinName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                color: Colors.white.withValues(alpha: .84),
                child: Column(
                  children: <Widget>[
                    Text(
                      selected!.tip,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: state.busy
                          ? null
                          : () async {
                              final result = await state.selectPlant(
                                widget.deviceId,
                                selected!,
                              );
                              if (!context.mounted) return;
                              showAppMessage(
                                context,
                                result.message,
                                success: result.success,
                              );
                              if (result.success) {
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  AppRoutes.device,
                                  (route) =>
                                      route.settings.name == AppRoutes.shell,
                                  arguments: widget.deviceId,
                                );
                              }
                            },
                      child: const Text('确认选择'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
