import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';

/// `touch_vib_switch` (123) and `touch_plant_vib_switch` (124).
///
/// The device splits haptics into the key press and the plant touch, and both
/// are readable and writable. They sit in their own card rather than inside
/// `VibrationSettingsCard` because that card's geometry comes from the Figma
/// frame, which only draws the master switch.
class VibrationSceneSwitchesCard extends StatelessWidget {
  const VibrationSceneSwitchesCard({
    required this.keyVibration,
    required this.plantVibration,
    required this.onKeyVibrationChanged,
    required this.onPlantVibrationChanged,
    super.key,
    this.updatingKeyVibration = false,
    this.updatingPlantVibration = false,
  });

  final bool keyVibration;
  final bool plantVibration;
  final ValueChanged<bool>? onKeyVibrationChanged;
  final ValueChanged<bool>? onPlantVibrationChanged;
  final bool updatingKeyVibration;
  final bool updatingPlantVibration;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      padding: EdgeInsets.zero,
      showShadow: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _VibrationSceneRow(
            title: '触摸按键震动',
            description: '触碰机身按键时给出震动反馈。',
            value: keyVibration,
            switchKey: const Key('touch-key-vibration-switch'),
            updating: updatingKeyVibration,
            onChanged: onKeyVibrationChanged,
          ),
          const Divider(height: 1, indent: 22, endIndent: 22),
          _VibrationSceneRow(
            title: '触摸植物震动',
            description: '触碰植物时给出震动反馈。',
            value: plantVibration,
            switchKey: const Key('touch-plant-vibration-switch'),
            updating: updatingPlantVibration,
            onChanged: onPlantVibrationChanged,
          ),
        ],
      ),
    );
  }
}

class _VibrationSceneRow extends StatelessWidget {
  const _VibrationSceneRow({
    required this.title,
    required this.description,
    required this.value,
    required this.switchKey,
    required this.updating,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final Key switchKey;
  final bool updating;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppTypography.sectionTitle.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: .86,
              alignment: Alignment.centerRight,
              child: Switch(
                key: switchKey,
                value: value,
                onChanged: updating ? null : onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
