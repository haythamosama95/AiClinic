import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';

/// Horizontal wizard stepper for clinic setup (Organization → Branch → Staff).
class SetupStepIndicator extends StatelessWidget {
  const SetupStepIndicator({required this.current, super.key});

  final SetupWizardStep current;

  static const _labels = ['Organization', 'Branch', 'Staff'];

  int get _currentIndex => switch (current) {
    SetupWizardStep.organization => 0,
    SetupWizardStep.branch => 1,
    SetupWizardStep.staff || SetupWizardStep.complete => 2,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final inactive = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
    final connectorColor = theme.colorScheme.outlineVariant;

    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xs),
                child: Divider(color: connectorColor, height: 1, thickness: 1),
              ),
            ),
          _StepNode(
            index: i + 1,
            label: _labels[i],
            isActive: i == _currentIndex,
            isComplete: i < _currentIndex,
            activeColor: primary,
            inactiveColor: inactive,
          ),
        ],
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.index,
    required this.label,
    required this.isActive,
    required this.isComplete,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int index;
  final String label;
  final bool isActive;
  final bool isComplete;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlighted = isActive || isComplete;
    final circleColor = highlighted ? activeColor : inactiveColor.withValues(alpha: 0.25);
    final textColor = highlighted ? activeColor : inactiveColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
          child: isComplete
              ? Icon(Icons.check, size: 16, color: theme.colorScheme.onPrimary)
              : Text(
                  '$index',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: highlighted ? theme.colorScheme.onPrimary : inactiveColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: textColor,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
