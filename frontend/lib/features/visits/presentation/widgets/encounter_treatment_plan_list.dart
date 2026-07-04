import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_catalog_field.dart';

/// Treatment plan lines with medication catalog autocomplete (013 US3).
class EncounterTreatmentPlanList extends ConsumerWidget {
  const EncounterTreatmentPlanList({
    required this.visitId,
    required this.treatmentPlans,
    required this.canEdit,
    super.key,
  });

  final String visitId;
  final List<TreatmentPlanItem> treatmentPlans;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;

    return AppCard(
      padding: AppCardPadding.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: 'Treatment plan',
            description: 'Prescribed medications for this visit',
            actions: canEdit
                ? AppButton(
                    label: 'Add medication',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    leadingIcon: LucideIcons.plus,
                    onPressed: () => _showAddDialog(context, ref),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.s3),
          if (treatmentPlans.isEmpty)
            const AppEmptyState(
              variant: AppEmptyStateVariant.noResults,
              title: 'No treatment plans',
              description: 'Add medications prescribed during this visit.',
            )
          else
            for (final plan in treatmentPlans)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.borderSubtle),
                    borderRadius: AppRadii.mdAll,
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.medicationName,
                                style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_subtitle(plan).isNotEmpty)
                                Text(
                                  _subtitle(plan),
                                  style: typography.bodySm.copyWith(color: colors.textSecondary),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (plan.notes != null && plan.notes!.trim().isNotEmpty)
                                Text(
                                  plan.notes!,
                                  style: typography.caption.copyWith(color: colors.textTertiary),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (canEdit)
                          AppIconButton(
                            icon: LucideIcons.trash2,
                            semanticLabel: 'Remove ${plan.medicationName}',
                            size: AppIconButtonSize.sm,
                            variant: AppIconButtonVariant.ghost,
                            onPressed: () => ref
                                .read(visitDocumentationProvider(visitId).notifier)
                                .stageArchiveTreatmentPlan(plan.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static String _subtitle(TreatmentPlanItem plan) {
    return [
      if (plan.dosage != null && plan.dosage!.isNotEmpty) plan.dosage!,
      if (plan.frequency != null && plan.frequency!.isNotEmpty) plan.frequency!,
      if (plan.duration != null && plan.duration!.isNotEmpty) plan.duration!,
    ].join(' · ');
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    await showAppDialog<void>(
      context,
      size: AppDialogSize.md,
      semanticLabel: 'Add medication',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Add medication',
          onClose: () => close(),
          body: _TreatmentPlanForm(
            onCancel: () => close(),
            onSubmit: (data) {
              ref.read(visitDocumentationProvider(visitId).notifier).stageCreateTreatmentPlan(
                    medicationName: data.medicationName,
                    medicationId: data.medicationId,
                    dosage: data.dosage,
                    frequency: data.frequency,
                    duration: data.duration,
                    notes: data.notes,
                  );
              close();
            },
          ),
        );
      },
    );
  }
}

class _TreatmentPlanFormData {
  const _TreatmentPlanFormData({
    required this.medicationName,
    this.medicationId,
    this.dosage,
    this.frequency,
    this.duration,
    this.notes,
  });

  final String medicationName;
  final String? medicationId;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final String? notes;
}

class _TreatmentPlanForm extends ConsumerStatefulWidget {
  const _TreatmentPlanForm({
    required this.onSubmit,
    required this.onCancel,
  });

  final ValueChanged<_TreatmentPlanFormData> onSubmit;
  final VoidCallback onCancel;

  @override
  ConsumerState<_TreatmentPlanForm> createState() => _TreatmentPlanFormState();
}

class _TreatmentPlanFormState extends ConsumerState<_TreatmentPlanForm> {
  CatalogFieldSelection _medication = const CatalogFieldSelection(name: '');
  final _dosageController = TextEditingController();
  final _frequencyController = TextEditingController();
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _dosageController.dispose();
    _frequencyController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EncounterCatalogField(
          label: 'Medication',
          onSearch: (query) => searchMedicationCatalog(ref, query),
          onSelectionChanged: (selection) => setState(() => _medication = selection),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Dosage',
          child: AppTextField(controller: _dosageController, hintText: '500 mg'),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Frequency',
          child: AppTextField(controller: _frequencyController, hintText: 'Twice daily'),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Duration',
          child: AppTextField(controller: _durationController, hintText: '7 days'),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Notes',
          child: AppTextArea(controller: _notesController, hintText: 'Optional'),
        ),
        const SizedBox(height: AppSpacing.s4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: widget.onCancel,
            ),
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              label: 'Add',
              size: AppButtonSize.sm,
              onPressed: () {
                final name = CatalogNameNormalizer.normalize(_medication.name);
                if (name.isEmpty) return;
                widget.onSubmit(
                  _TreatmentPlanFormData(
                    medicationName: name,
                    medicationId: _medication.catalogId,
                    dosage: _dosageController.text.trim(),
                    frequency: _frequencyController.text.trim(),
                    duration: _durationController.text.trim(),
                    notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
