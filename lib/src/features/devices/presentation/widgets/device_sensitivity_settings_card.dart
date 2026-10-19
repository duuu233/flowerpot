import 'package:flutter/material.dart';

import '../../../../design_system/design_system.dart';
import 'setting_orbit_illustration.dart';

class DeviceSensitivitySettingsCard extends StatelessWidget {
  const DeviceSensitivitySettingsCard({
    required this.symbol,
    required this.title,
    required this.status,
    required this.description,
    required this.descriptionLines,
    required this.interactionEnabled,
    required this.interactionSwitchKey,
    required this.sensitivity,
    required this.sensitivitySliderKey,
    required this.onInteractionChanged,
    required this.onSensitivityChanged,
    required this.onSensitivityChangeEnd,
    super.key,
    this.updatingInteraction = false,
    this.updatingSensitivity = false,
    this.sliderLabel = '传感器灵敏度',
    this.sliderLocked = false,
  });

  final DeviceSettingSymbol symbol;
  final String title;
  final String status;
  final String description;
  final List<String> descriptionLines;
  final bool interactionEnabled;
  final Key interactionSwitchKey;
  final double sensitivity;
  final Key sensitivitySliderKey;
  final ValueChanged<bool>? onInteractionChanged;
  final ValueChanged<double>? onSensitivityChanged;
  final ValueChanged<double>? onSensitivityChangeEnd;
  final bool updatingInteraction;
  final bool updatingSensitivity;

  /// 滑条那一行的标题，默认「传感器灵敏度」；显示页用它画「屏幕亮度」。
  final String sliderLabel;

  /// 滑条整体不可拖（显示页自动亮度开着时手动亮度不生效）。
  final bool sliderLocked;

  @override
  Widget build(BuildContext context) {
    final sliderEnabled = !updatingSensitivity && !sliderLocked;
    return AppSurfaceCard(
      color: AppColors.surfaceTranslucent,
      borderRadius: AppRadius.large,
      padding: EdgeInsets.zero,
      showShadow: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 184,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(
                top: DeviceSettingOrbitIllustration.topInset,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: DeviceSettingOrbitIllustration(symbol: symbol),
              ),
            ),
          ),
          SizedBox(
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
                          status,
                          style: AppTypography.sectionTitle.copyWith(
                            color: AppColors.brandPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: .86,
                    alignment: Alignment.centerRight,
                    child: Switch(
                      key: interactionSwitchKey,
                      value: interactionEnabled,
                      onChanged: updatingInteraction
                          ? null
                          : onInteractionChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(indent: 22, endIndent: 22),
          SizedBox(
            height: 172,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 19, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: 38,
                    child: Semantics(
                      label: description,
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            for (final line in descriptionLines)
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    line,
                                    maxLines: 1,
                                    style: AppTypography.body.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      Text(
                        sliderLabel,
                        style: AppTypography.sectionTitle.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 1,
                        height: 17,
                        color: AppColors.textSecondary.withValues(alpha: .45),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '${sensitivity.round()}%',
                        style: AppTypography.sectionTitle.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 32,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.brandPrimary,
                        inactiveTrackColor: const Color(0xFFEAEAEA),
                        disabledActiveTrackColor: AppColors.brandPrimary
                            .withValues(alpha: .45),
                        disabledInactiveTrackColor: const Color(0xFFF0F0F0),
                        trackHeight: 14,
                        thumbColor: Colors.white,
                        disabledThumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10,
                          elevation: 3,
                          pressedElevation: 4,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        showValueIndicator: ShowValueIndicator.never,
                      ),
                      child: Slider(
                        key: sensitivitySliderKey,
                        value: sensitivity.clamp(0, 100),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: sliderEnabled ? onSensitivityChanged : null,
                        onChangeEnd: sliderEnabled
                            ? onSensitivityChangeEnd
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
