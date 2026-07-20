import 'package:flutter/material.dart';

import '../../tokens/app_colors.dart';
import '../../tokens/app_spacing.dart';

class AppStepIndicator extends StatelessWidget {
  const AppStepIndicator({
    required this.stepCount,
    required this.currentStep,
    super.key,
  }) : assert(stepCount > 0),
       assert(currentStep >= 0 && currentStep < stepCount);

  final int stepCount;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var index = 0; index < stepCount; index++) ...<Widget>[
          _StepCircle(
            index: index,
            active: index <= currentStep,
            current: index == currentStep,
          ),
          if (index < stepCount - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                color: index < currentStep
                    ? AppColors.brandPrimary
                    : AppColors.divider,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.index,
    required this.active,
    required this.current,
  });

  final int index;
  final bool active;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: current ? 24 : 22,
      height: current ? 24 : 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.brandPrimary : AppColors.divider,
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1}',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.surface),
      ),
    );
  }
}
