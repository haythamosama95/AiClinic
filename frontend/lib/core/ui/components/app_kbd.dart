import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Single keyboard glyph chip (web `KbdKey`).
class AppKbdKey extends StatelessWidget {
  const AppKbdKey({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.borderDefault),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space1 + AppSpacing.space05,
            vertical: AppSpacing.space05,
          ),
          child: DefaultTextStyle(
            style: AppTypography.mono(
              context,
            ).copyWith(fontSize: AppTypography.caption(context).fontSize, color: colors.textSecondary),
            textAlign: TextAlign.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Keyboard shortcut hint — single key via [child] or chord via [keys] (web `Kbd`).
class AppKbd extends StatelessWidget {
  const AppKbd({this.child, this.keys, super.key}) : assert(child != null || keys != null);

  final Widget? child;
  final List<String>? keys;

  @override
  Widget build(BuildContext context) {
    if (keys != null) {
      final colors = context.appColors;
      final separatorStyle = AppTypography.caption(context).copyWith(color: colors.textTertiary);

      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.space1,
        children: [
          for (var i = 0; i < keys!.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i > 0) ...[Text('+', style: separatorStyle), const SizedBox(width: AppSpacing.space05)],
                AppKbdKey(child: Text(keys![i])),
              ],
            ),
        ],
      );
    }

    return AppKbdKey(child: child!);
  }
}
