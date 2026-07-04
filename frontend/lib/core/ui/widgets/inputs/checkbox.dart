import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppCheckboxState { unchecked, checked, indeterminate }

/// Checkbox with optional label and indeterminate state.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    this.id,
    this.value = AppCheckboxState.unchecked,
    this.onChanged,
    this.disabled = false,
    this.invalid = false,
    this.label,
  });

  final String? id;
  final AppCheckboxState value;
  final ValueChanged<AppCheckboxState>? onChanged;
  final bool disabled;
  final bool invalid;
  final String? label;

  void _toggle() {
    if (disabled || onChanged == null) return;
    final next = value == AppCheckboxState.checked
        ? AppCheckboxState.unchecked
        : AppCheckboxState.checked;
    onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final reducedMotion = AppMotion.isReducedMotion(context);
    final checked = value != AppCheckboxState.unchecked;
    final isIndeterminate = value == AppCheckboxState.indeterminate;

    final boxColor = checked ? colors.actionPrimary : colors.surfaceDefault;
    final borderColor = invalid
        ? colors.statusDangerBorder
        : checked
        ? colors.actionPrimary
        : colors.borderDefault;

    final control = Semantics(
      checked: isIndeterminate ? null : value == AppCheckboxState.checked,
      identifier: id,
      child: AnimatedContainer(
        duration: reducedMotion ? Duration.zero : AppDurations.fast,
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: boxColor,
          borderRadius: AppRadius.smAll,
          border: Border.all(color: borderColor),
        ),
        child: checked
            ? Icon(
                isIndeterminate ? Icons.remove : Icons.check,
                size: 14,
                color: colors.actionPrimaryFg,
              )
            : null,
      ),
    );

    final tappable = InkWell(
      onTap: disabled ? null : _toggle,
      borderRadius: AppRadius.smAll,
      child: control,
    );

    if (label == null) return tappable;

    return InkWell(
      onTap: disabled ? null : _toggle,
      borderRadius: AppRadius.mdAll,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tappable,
          const SizedBox(width: AppSpacing.s2),
          Text(
            label!,
            style: typography.body.copyWith(
              color: disabled ? colors.textDisabled : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
