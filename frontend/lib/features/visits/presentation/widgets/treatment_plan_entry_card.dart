import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_options.dart';

/// Compact card for a single prescription line.
class TreatmentPlanEntryCard extends StatelessWidget {
  const TreatmentPlanEntryCard({
    required this.medicationName,
    this.dosage,
    this.frequency,
    this.duration,
    this.onEdit,
    this.onRemove,
    this.canEdit = true,
    super.key,
  });

  final String medicationName;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final trimmedDosage = dosage?.trim();
    final hasDosage = trimmedDosage != null && trimmedDosage.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: ColoredBox(color: colors.actionPrimary.withValues(alpha: 0.5), child: const SizedBox(width: 3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                AppSpacing.space2 + 2,
                AppSpacing.space2,
                AppSpacing.space2 + 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 4,
                    child: _FieldColumn(label: 'Medication', value: medicationName, emphasized: true),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    flex: 2,
                    child: _FieldColumn(label: 'Dosage', value: hasDosage ? trimmedDosage : '—', muted: !hasDosage),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    flex: 3,
                    child: _FieldColumn(
                      label: 'Frequency',
                      value: treatmentFrequencyLabel(frequency),
                      muted: frequency == null || frequency!.trim().isEmpty,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    flex: 2,
                    child: _FieldColumn(
                      label: 'Duration',
                      value: treatmentDurationLabel(duration),
                      muted: duration == null || duration!.trim().isEmpty,
                    ),
                  ),
                  if (canEdit) ...[
                    AppIconButton(
                      icon: Icon(Icons.edit_outlined, size: 15, color: colors.iconMuted),
                      label: 'Edit $medicationName',
                      size: AppIconButtonSize.sm,
                      tooltipDisabled: true,
                      onPressed: onEdit,
                    ),
                    AppIconButton(
                      icon: Icon(Icons.delete_outline, size: 15, color: colors.iconMuted),
                      label: 'Remove $medicationName',
                      size: AppIconButtonSize.sm,
                      tooltipDisabled: true,
                      onPressed: onRemove,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldColumn extends StatelessWidget {
  const _FieldColumn({required this.label, required this.value, this.emphasized = false, this.muted = false});

  final String label;
  final String value;
  final bool emphasized;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.caption(
            context,
          ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w500, letterSpacing: 0.6),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          value,
          style: (emphasized ? AppTypography.bodyStrong(context) : AppTypography.bodySm(context)).copyWith(
            color: muted ? colors.textTertiary : (emphasized ? colors.textPrimary : colors.textSecondary),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
