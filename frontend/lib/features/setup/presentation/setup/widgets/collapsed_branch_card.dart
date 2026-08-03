import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/collapsed_summary_enter_transition.dart';

/// Collapsed branch summary row (web `CollapsedBranchCard`).
class CollapsedBranchCard extends StatelessWidget {
  const CollapsedBranchCard({
    required this.branch,
    required this.index,
    required this.onExpand,
    required this.onRemove,
    super.key,
  });

  final BranchDraft branch;
  final int index;
  final VoidCallback onExpand;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final openDays = branch.workingDays.where((day) => day.enabled).length;
    final subtitle = [
      if (branch.code.isNotEmpty) branch.code,
      if (branch.mobile.isNotEmpty) branch.mobile,
      '$openDays open days',
    ].join(' · ');

    return CollapsedSummaryEnterTransition(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Material(
              color: colors.surfaceMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: InkWell(
                onTap: onExpand,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                hoverColor: colors.surfaceHover,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: colors.borderDefault),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceDefault,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: const SizedBox(
                            width: 36,
                            height: 36,
                            child: Icon(Icons.location_on, size: 16, color: AppColorPrimitives.violet600),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                branch.name.isNotEmpty ? branch.name : 'Branch ${index + 1}',
                                style: AppTypography.bodyStrong(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                subtitle,
                                style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 16, color: colors.iconMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.space2),
          AppIconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: 'Remove branch',
            variant: AppIconButtonVariant.danger,
            size: AppIconButtonSize.md,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
