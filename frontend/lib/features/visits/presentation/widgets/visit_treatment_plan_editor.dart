import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_form_dialog.dart';

typedef TreatmentPlanCreateHandler =
    void Function({
      required String medicationName,
      String? medicationId,
      String? dosage,
      String? frequency,
      String? duration,
      String? notes,
    });

typedef TreatmentPlanUpdateHandler =
    void Function(
      String id, {
      String? medicationName,
      String? medicationId,
      String? dosage,
      String? frequency,
      String? duration,
      String? notes,
    });

typedef TreatmentPlanArchiveHandler = void Function(String id);

/// Prescription lines for the treatment step.
class VisitTreatmentPlanEditor extends StatelessWidget {
  const VisitTreatmentPlanEditor({
    required this.entries,
    required this.onCreate,
    required this.onUpdate,
    required this.onArchive,
    this.canEdit = true,
    super.key,
  });

  final List<TreatmentPlanItem> entries;
  final TreatmentPlanCreateHandler onCreate;
  final TreatmentPlanUpdateHandler onUpdate;
  final TreatmentPlanArchiveHandler onArchive;
  final bool canEdit;

  Future<void> _openDialog(BuildContext context, {TreatmentPlanItem? editing}) async {
    final result = await TreatmentPlanFormDialog.show(context, editingEntry: editing);
    if (result == null) {
      return;
    }

    if (editing != null) {
      onUpdate(
        editing.id,
        medicationName: result.medicationName,
        medicationId: result.medicationId,
        dosage: result.dosage,
        frequency: result.frequency,
        duration: result.duration,
      );
      return;
    }

    onCreate(
      medicationName: result.medicationName,
      medicationId: result.medicationId,
      dosage: result.dosage,
      frequency: result.frequency,
      duration: result.duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Prescriptions', style: AppTypography.title(context).copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.space1),
            Text(
              entries.isEmpty
                  ? 'Add medications with dosage, frequency, and duration.'
                  : '${entries.length} prescription${entries.length == 1 ? '' : 's'} added',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space4),
            if (entries.isEmpty)
              _EmptyTreatmentPlanState(canEdit: canEdit, onAdd: () => _openDialog(context))
            else ...[
              Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.space3),
                    TreatmentPlanEntryCard(
                      medicationName: entries[i].medicationName,
                      dosage: entries[i].dosage,
                      frequency: entries[i].frequency,
                      duration: entries[i].duration,
                      canEdit: canEdit,
                      onEdit: canEdit ? () => _openDialog(context, editing: entries[i]) : null,
                      onRemove: canEdit ? () => onArchive(entries[i].id) : null,
                    ),
                  ],
                ],
              ),
              if (canEdit) ...[
                const SizedBox(height: AppSpacing.space4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    leadingIcon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: () => _openDialog(context),
                    child: const Text('Add another prescription'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyTreatmentPlanState extends StatelessWidget {
  const _EmptyTreatmentPlanState({required this.canEdit, required this.onAdd});

  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space6),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.surfaceRaised, shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space2 + 2),
                child: Icon(Icons.medication_outlined, size: 18, color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'No prescriptions added yet.',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (canEdit) ...[
              const SizedBox(height: AppSpacing.space4),
              AppButton(
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: const Icon(Icons.add_rounded, size: 16),
                onPressed: onAdd,
                child: const Text('Add prescription'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
