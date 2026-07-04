import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppRadioOrientation { vertical, horizontal }

/// Single option in [AppRadioGroup].
class AppRadioOption {
  const AppRadioOption({
    required this.value,
    required this.label,
    this.disabled = false,
  });

  final String value;
  final String label;
  final bool disabled;
}

/// Radio button group with vertical or horizontal layout.
class AppRadioGroup extends StatelessWidget {
  const AppRadioGroup({
    super.key,
    this.value,
    this.onValueChange,
    this.options = const [],
    this.orientation = AppRadioOrientation.vertical,
    this.disabled = false,
    this.invalid = false,
  });

  final String? value;
  final ValueChanged<String>? onValueChange;
  final List<AppRadioOption> options;
  final AppRadioOrientation orientation;
  final bool disabled;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = orientation == AppRadioOrientation.horizontal;

    return Flex(
      direction: isHorizontal ? Axis.horizontal : Axis.vertical,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0)
            isHorizontal
                ? const SizedBox(width: AppSpacing.s3)
                : const SizedBox(height: AppSpacing.s3),
          _RadioTile(
            option: options[i],
            groupValue: value,
            disabled: disabled,
            invalid: invalid,
            onChanged: onValueChange,
          ),
        ],
      ],
    );
  }
}

class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.option,
    required this.groupValue,
    required this.disabled,
    required this.invalid,
    required this.onChanged,
  });

  final AppRadioOption option;
  final String? groupValue;
  final bool disabled;
  final bool invalid;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final reducedMotion = AppMotion.isReducedMotion(context);
    final isDisabled = disabled || option.disabled;
    final selected = groupValue == option.value;

    return InkWell(
      onTap: isDisabled || onChanged == null
          ? null
          : () => onChanged!(option.value),
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: reducedMotion ? Duration.zero : AppDurations.fast,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceDefault,
              border: Border.all(
                color: invalid
                    ? colors.statusDangerBorder
                    : selected
                    ? colors.actionPrimary
                    : colors.borderDefault,
              ),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.actionPrimary,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: AppSpacing.s2),
          Text(
            option.label,
            style: typography.body.copyWith(
              color: isDisabled ? colors.textDisabled : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
