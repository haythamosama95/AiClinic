import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_chip.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Active search and filter chips strip (web `ListControlBar` `activeFilters` region).
class PatientActiveFiltersBar extends StatelessWidget {
  const PatientActiveFiltersBar({
    required this.active,
    this.onClearAll,
    super.key,
  });

  final List<({String id, String label, VoidCallback onRemove})> active;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final duration = reducedMotion ? Duration.zero : AppMotion.quick;

    return ClipRect(
      child: AnimatedSize(
        duration: duration,
        curve: AppMotion.outCurve,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: AppMotion.outCurve,
          switchOutCurve: AppMotion.inCurve,
          child: active.isEmpty
              ? const SizedBox.shrink(key: ValueKey<String>('patient-active-filters-empty'))
              : _ActiveFiltersContent(
                  key: const ValueKey<String>('patient-active-filters'),
                  active: active,
                  onClearAll: onClearAll,
                ),
        ),
      ),
    );
  }
}

class _ActiveFiltersContent extends StatelessWidget {
  const _ActiveFiltersContent({
    required this.active,
    this.onClearAll,
    super.key,
  });

  final List<({String id, String label, VoidCallback onRemove})> active;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 640 ? AppSpacing.space5 : AppSpacing.space4;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: colors.borderSubtle.withValues(alpha: 0.8))),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: AppSpacing.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.tune, size: 13, color: colors.iconMuted),
                  Text(
                    'Filtered by',
                    style: AppTypography.caption(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textTertiary,
                    ),
                  ),
                  for (final filter in active)
                    AppChip(
                      key: ValueKey<String>(filter.id),
                      removable: true,
                      onRemove: filter.onRemove,
                      child: Text(filter.label),
                    ),
                ],
              ),
            ),
            if (onClearAll != null) ...[
              const SizedBox(width: AppSpacing.space2),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.textLink,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onClearAll,
                child: Text(
                  'Clear all',
                  style: AppTypography.caption(context).copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textLink,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
