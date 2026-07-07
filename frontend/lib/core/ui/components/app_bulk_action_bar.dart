import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Floating bar for bulk selection actions (web `BulkActionBar`).
class AppBulkActionBar extends StatelessWidget {
  const AppBulkActionBar({
    required this.count,
    required this.onClear,
    this.itemLabel = 'selected',
    this.actions,
    super.key,
  });

  final int count;
  final String itemLabel;
  final Widget? actions;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final elevation = Theme.of(context).extension<AppElevation>()!;

    return Semantics(
      container: true,
      label: 'Bulk actions',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          border: Border.all(color: colors.borderDefault),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: isDark ? elevation.shadows2 : elevation.shadows2,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space2,
            children: [
              Text(
                '$count $itemLabel',
                style: AppTypography.bodyStrong(context).copyWith(
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Wrap(
                spacing: AppSpacing.space2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ?actions,
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: onClear,
                    leadingIcon: const Icon(Icons.close, size: 14),
                    child: const Text('Clear selection'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
