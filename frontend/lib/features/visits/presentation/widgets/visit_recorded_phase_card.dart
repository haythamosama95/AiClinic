import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Success-border mini-card for a documented visit phase (web `RecordedPhase`).
class VisitRecordedPhaseCard extends StatelessWidget {
  const VisitRecordedPhaseCard({
    required this.label,
    required this.icon,
    super.key,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: colors.statusSuccessBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space3,
            vertical: 14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.statusSuccessSurface,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    icon,
                    size: 16,
                    color: colors.statusSuccessFg,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTypography.caption(context).copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.space1),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 11,
                    color: colors.statusSuccessFg,
                  ),
                  const SizedBox(width: AppSpacing.space1),
                  Text(
                    'Recorded',
                    style: AppTypography.caption(context).copyWith(
                      color: colors.statusSuccessFg,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
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
