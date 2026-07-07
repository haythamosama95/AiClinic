import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Small bordered monospace keyboard glyph (web `Kbd`).
class AppKbd extends StatelessWidget {
  const AppKbd({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1 + AppSpacing.space05, vertical: AppSpacing.space05),
        child: DefaultTextStyle(
          style: AppTypography.mono(context).copyWith(color: colors.textSecondary),
          child: child,
        ),
      ),
    );
  }
}
