import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Warning strip summarizing queue health issues (web `QueueAlertBanner`).
///
/// Uses the App warning surface tokens (`statusWarningSurface` / `statusWarningBorder`
/// / `statusWarningFg`) in a card-shaped container matching [AppCard] radius and padding.
class QueueAlertBanner extends StatelessWidget {
  const QueueAlertBanner({
    required this.issues,
    this.onDismiss,
    super.key,
  });

  final List<String> issues;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final message = issues.join(' · ');

    return Semantics(
      role: SemanticsRole.alert,
      label: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.statusWarningSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.statusWarningBorder),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.space4,
            vertical: 10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: colors.statusWarningFg,
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    Expanded(
                      child: Text(
                        message,
                        style: AppTypography.bodySm(context).copyWith(
                          color: colors.statusWarningFg,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onDismiss != null) ...[
                const SizedBox(width: AppSpacing.space3),
                AppButton(
                  variant: AppButtonVariant.link,
                  size: AppButtonSize.sm,
                  onPressed: onDismiss,
                  child: Text(
                    'Dismiss',
                    style: AppTypography.caption(context).copyWith(
                      color: colors.statusWarningFg,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
