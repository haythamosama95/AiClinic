import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Centered error placeholder with optional retry (web `ErrorState`).
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.message,
    this.title = 'Failed to load',
    this.onRetry,
    this.retryLabel = 'Try again',
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  static const _maxMessageWidth = 384.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dangerSurface = isDark ? AppColorPrimitives.statusDangerSurfaceDark : AppColorPrimitives.red50;

    return Semantics(
      role: SemanticsRole.alert,
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space6,
          vertical: AppSpacing.space12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: dangerSurface,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: AppSpacing.space12,
                height: AppSpacing.space12,
                child: Icon(
                  Icons.warning,
                  size: 24,
                  color: colors.statusDangerFg,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              title,
              style: AppTypography.h3(context).copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxMessageWidth),
              child: Text(
                message,
                style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.space6),
              AppButton(
                variant: AppButtonVariant.secondary,
                onPressed: onRetry,
                leadingIcon: const Icon(Icons.refresh),
                child: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
