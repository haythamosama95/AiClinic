import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_entry_list.dart';

/// Treatment plan prescriptions editor (web `TreatmentPlanEditor`).
class TreatmentPlanEditor extends ConsumerStatefulWidget {
  const TreatmentPlanEditor({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<TreatmentPlanEditor> createState() => _TreatmentPlanEditorState();
}

class _TreatmentPlanEditorState extends ConsumerState<TreatmentPlanEditor> {
  var _dialogOpen = false;
  String? _editingId;

  void _openAddDialog() {
    setState(() {
      _editingId = null;
      _dialogOpen = true;
    });
  }

  void _openEditDialog(String id) {
    setState(() {
      _editingId = id;
      _dialogOpen = true;
    });
  }

  void _handleDialogOpenChange(bool open) {
    setState(() {
      _dialogOpen = open;
      if (!open) {
        _editingId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(visitDocumentationProvider(widget.visitId));
    final state = doc.value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final canEdit = state.canEditWorkspace(ref.read(permissionServiceProvider).canEditVisitSoap());
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final plans = state.effectiveVisit.treatmentPlans;
    final editingEntry =
        _editingId == null ? null : plans.where((plan) => plan.id == _editingId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prescriptions',
                  style: AppTypography.title(context).copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space05),
                Text(
                  plans.isNotEmpty
                      ? '${plans.length} prescription${plans.length == 1 ? '' : 's'} added'
                      : 'Add medications with dosage, frequency, and duration.',
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space4),
                if (plans.isEmpty)
                  _EmptyTreatmentPlanState(
                    canEdit: canEdit,
                    onAdd: _openAddDialog,
                  )
                else
                  VisitEntryList<TreatmentPlanItem>(
                    items: plans,
                    itemId: (plan) => plan.id,
                    wrap: true,
                    maxCrossAxisCount: 4,
                    itemBuilder: (context, plan) => TreatmentPlanEntryCard(
                      medicationName: plan.medicationName,
                      dosage: plan.dosage,
                      frequency: plan.frequency,
                      duration: plan.duration,
                      onEdit: canEdit ? () => _openEditDialog(plan.id) : null,
                      onRemove: canEdit ? () => notifier.stageArchiveTreatmentPlan(plan.id) : null,
                    ),
                  ),
                if (plans.isNotEmpty && canEdit) ...[
                  const SizedBox(height: AppSpacing.space4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton(
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.sm,
                      leadingIcon: const Icon(Icons.add, size: 14),
                      onPressed: _openAddDialog,
                      child: const Text('Add another prescription'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        TreatmentPlanFormDialog(
          open: _dialogOpen,
          onOpenChange: _handleDialogOpenChange,
          editingEntry: editingEntry,
          onSubmit: ({
            required medicationName,
            medicationId,
            required dosage,
            required frequency,
            required duration,
          }) {
            if (_editingId != null) {
              notifier.stageUpdateTreatmentPlan(
                treatmentPlanId: _editingId!,
                medicationName: medicationName,
                medicationId: medicationId,
                dosage: dosage,
                frequency: frequency,
                duration: duration,
              );
            } else {
              notifier.stageCreateTreatmentPlan(
                medicationName: medicationName,
                medicationId: medicationId,
                dosage: dosage,
                frequency: frequency,
                duration: duration,
              );
            }
          },
        ),
      ],
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

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: colors.borderDefault, style: BorderStyle.solid),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space8),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space3),
                  child: Icon(Icons.medical_services_outlined, size: 18, color: colors.textTertiary),
                ),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                'No prescriptions added yet.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space4),
              AppButton(
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: const Icon(Icons.add, size: 14),
                onPressed: canEdit ? onAdd : null,
                disabled: !canEdit,
                child: const Text('Add prescription'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
