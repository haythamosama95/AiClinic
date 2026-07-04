import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Keyboard shortcut chip reconciling web `Kbd` + `KbdKey` into one primitive.
///
/// Pass [keys] for chord hints (`⌘` + `K`) or [child] for a single key label.
class AppKbd extends StatelessWidget {
  const AppKbd({super.key, this.child, this.keys});

  final Widget? child;
  final List<String>? keys;

  /// Single-key convenience matching web `KbdKey`.
  factory AppKbd.single(String label, {Key? key}) {
    return AppKbd(key: key, child: Text(label));
  }

  @override
  Widget build(BuildContext context) {
    assert(child != null || (keys != null && keys!.isNotEmpty));
    if (keys != null) {
      return _AppKbdChord(keys: keys!);
    }
    return _AppKbdChip(child: child!);
  }
}

class _AppKbdChord extends StatelessWidget {
  const _AppKbdChord({required this.keys});

  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final children = <Widget>[];

    for (var i = 0; i < keys.length; i++) {
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s0_5),
            child: Text(
              '+',
              style: context.typography.caption.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
        );
      }
      children.add(_AppKbdChip(child: Text(keys[i])));
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _AppKbdChip extends StatelessWidget {
  const _AppKbdChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DefaultTextStyle(
      style: typography.mono.copyWith(color: colors.textSecondary),
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s1 + AppSpacing.s0_5,
          vertical: AppSpacing.s0_5,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: AppRadius.smAll,
          border: Border.all(color: colors.borderDefault),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
