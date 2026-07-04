import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Keyboard shortcut hint — renders one or more key chips.
class AppKbd extends StatelessWidget {
  const AppKbd({
    this.child,
    this.keys,
    super.key,
  }) : assert(child != null || keys != null);

  final Widget? child;
  final List<String>? keys;

  @override
  Widget build(BuildContext context) {
    if (child != null) {
      return child!;
    }

    final keyList = keys!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < keyList.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.s0_5,
              ),
              child: Text(
                '+',
                style: context.typography.caption.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
            ),
          AppKbdKey(label: keyList[i]),
        ],
      ],
    );
  }
}

/// Single keyboard key chip.
class AppKbdKey extends StatelessWidget {
  const AppKbdKey({
    required this.label,
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      constraints: const BoxConstraints(minWidth: AppSpacing.s5),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s1 + AppSpacing.s0_5,
        vertical: AppSpacing.s0_5,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadii.smAll,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: typography.mono.copyWith(
          fontSize: typography.caption.fontSize,
          height: typography.caption.height,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
