import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Toggle switch with optional label.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    this.id,
    this.value = false,
    this.onChanged,
    this.disabled = false,
    this.invalid = false,
    this.label,
  });

  final String? id;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool disabled;
  final bool invalid;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final reducedMotion = AppMotion.isReducedMotion(context);
    final rtl = context.isRtl;
    const trackWidth = 44.0;
    const thumbSize = 20.0;
    const padding = 2.0;

    final control = Semantics(
      identifier: id,
      toggled: value,
      child: InkWell(
        onTap: disabled || onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(9999),
        child: AnimatedContainer(
          duration: reducedMotion ? Duration.zero : AppDurations.fast,
          width: trackWidth,
          height: 24,
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: value ? colors.actionPrimary : colors.surfaceMuted,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: invalid
                  ? colors.statusDangerBorder
                  : value
                  ? colors.actionPrimary
                  : colors.borderDefault,
            ),
          ),
          child: AnimatedAlign(
            duration: reducedMotion ? Duration.zero : AppDurations.fast,
            alignment: rtl
                ? (value ? Alignment.centerLeft : Alignment.centerRight)
                : (value ? Alignment.centerRight : Alignment.centerLeft),
            child: Container(
              width: thumbSize,
              height: thumbSize,
              decoration: BoxDecoration(
                color: colors.surfaceDefault,
                shape: BoxShape.circle,
                boxShadow: context.elevation.level1,
              ),
            ),
          ),
        ),
      ),
    );

    if (label == null) return control;

    return InkWell(
      onTap: disabled || onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          control,
          const SizedBox(width: AppSpacing.s3),
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
