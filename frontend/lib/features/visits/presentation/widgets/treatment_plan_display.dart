import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';

/// Shared treatment plan presentation for documentation, detail, and list views.
class TreatmentPlanDisplay {
  TreatmentPlanDisplay._();

  /// Subtitle segments for a treatment plan card (dosage · frequency · duration).
  static List<String> subtitleParts(TreatmentPlanItem plan) {
    final parts = <String>[
      if (plan.dosage != null && plan.dosage!.isNotEmpty) plan.dosage!,
      if (plan.frequency != null && plan.frequency!.isNotEmpty) plan.frequency!,
      if (plan.duration != null && plan.duration!.isNotEmpty) plan.duration!,
    ];
    final legacyDates = _legacyDateRange(plan.startDate, plan.endDate);
    if (legacyDates != null && parts.every((p) => p != legacyDates)) {
      parts.add(legacyDates);
    }
    return parts;
  }

  static String? _legacyDateRange(DateTime? start, DateTime? end) {
    final fmt = DateFormat.yMMMd();
    if (start != null && end != null) return '${fmt.format(start)} – ${fmt.format(end)}';
    if (start != null) return 'From ${fmt.format(start)}';
    if (end != null) return 'Until ${fmt.format(end)}';
    return null;
  }
}

/// Read-only treatment plan card used across visit screens.
class TreatmentPlanCardView extends StatelessWidget {
  const TreatmentPlanCardView({required this.plan, this.canEdit = false, this.onEdit, this.onArchive, super.key});

  final TreatmentPlanItem plan;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final subtitleParts = TreatmentPlanDisplay.subtitleParts(plan);

    return DecoratedBox(
      key: Key('treatment_plan_card_${plan.id}'),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.medication_outlined, size: 20, color: colors.primary),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.medicationName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitleParts.isNotEmpty) ...[
                    const SizedBox(height: SpacingTokens.xs),
                    Text(subtitleParts.join(' · '), style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (plan.notes != null && plan.notes!.isNotEmpty) ...[
                    const SizedBox(height: SpacingTokens.xs),
                    Text(plan.notes!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
                  ],
                ],
              ),
            ),
            if (canEdit)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    key: Key('treatment_plan_edit_${plan.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    onPressed: onEdit,
                  ),
                  AppIconButton(
                    key: Key('treatment_plan_archive_${plan.id}'),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Remove',
                    onPressed: onArchive,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Form data for creating or updating a treatment plan.
class TreatmentPlanFormData {
  TreatmentPlanFormData({required this.medicationName, this.dosage, this.frequency, this.duration, this.notes});

  final String medicationName;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final String? notes;

  ({String? medicationName, String? dosage, String? frequency, String? duration, String? notes}) updateParamsFor(
    TreatmentPlanItem existing,
  ) {
    final trimmedName = medicationName.trim();
    return (
      medicationName: trimmedName != existing.medicationName ? trimmedName : null,
      dosage: _optionalUpdateParam(existing.dosage, dosage),
      frequency: _optionalUpdateParam(existing.frequency, frequency),
      duration: _optionalUpdateParam(existing.duration, duration),
      notes: _optionalUpdateParam(existing.notes, notes),
    );
  }

  static String? _optionalUpdateParam(String? existing, String? submitted) {
    if (submitted == null) {
      return null;
    }
    if (_normalizeOptional(existing) == _normalizeOptional(submitted)) {
      return null;
    }
    return submitted;
  }

  static String? _normalizeOptional(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }
}

/// Add/edit treatment plan form shared across visit documentation.
class TreatmentPlanFormView extends StatefulWidget {
  const TreatmentPlanFormView({
    this.initialPlan,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  final TreatmentPlanItem? initialPlan;
  final bool isSubmitting;
  final void Function(TreatmentPlanFormData data) onSubmit;
  final VoidCallback onCancel;

  @override
  State<TreatmentPlanFormView> createState() => _TreatmentPlanFormViewState();
}

class _TreatmentPlanFormViewState extends State<TreatmentPlanFormView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _medication;
  late final TextEditingController _dosage;
  late final TextEditingController _frequency;
  late final TextEditingController _duration;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPlan;
    _medication = TextEditingController(text: p?.medicationName ?? '');
    _dosage = TextEditingController(text: p?.dosage ?? '');
    _frequency = TextEditingController(text: p?.frequency ?? '');
    _duration = TextEditingController(text: p?.duration ?? '');
    _notes = TextEditingController(text: p?.notes ?? '');
  }

  @override
  void dispose() {
    _medication.dispose();
    _dosage.dispose();
    _frequency.dispose();
    _duration.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialPlan != null;
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.md),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit treatment plan' : 'New treatment plan',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: SpacingTokens.md),
              AppTextField(
                key: const Key('treatment_plan_medication_field'),
                label: 'Medication name *',
                controller: _medication,
                enabled: !widget.isSubmitting,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: SpacingTokens.sm),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      key: const Key('treatment_plan_dosage_field'),
                      label: 'Dosage',
                      controller: _dosage,
                      enabled: !widget.isSubmitting,
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Expanded(
                    child: AppTextField(
                      key: const Key('treatment_plan_frequency_field'),
                      label: 'Frequency',
                      controller: _frequency,
                      enabled: !widget.isSubmitting,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTextField(
                key: const Key('treatment_plan_duration_field'),
                label: 'Duration',
                hintText: 'e.g. 7 days, 2 weeks',
                controller: _duration,
                enabled: !widget.isSubmitting,
              ),
              const SizedBox(height: SpacingTokens.sm),
              AppTextField(
                key: const Key('treatment_plan_notes_field'),
                label: 'Notes',
                controller: _notes,
                maxLines: 3,
                enabled: !widget.isSubmitting,
              ),
              const SizedBox(height: SpacingTokens.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    key: const Key('treatment_plan_cancel_button'),
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: widget.isSubmitting ? null : widget.onCancel,
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  AppButton(
                    key: const Key('treatment_plan_save_button'),
                    label: isEdit ? 'Update' : 'Add',
                    isLoading: widget.isSubmitting,
                    onPressed: widget.isSubmitting ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _optionalFieldForSubmit(String trimmed, {required bool isEdit}) {
    if (trimmed.isEmpty) {
      return isEdit ? '' : null;
    }
    return trimmed;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final isEdit = widget.initialPlan != null;
    widget.onSubmit(
      TreatmentPlanFormData(
        medicationName: _medication.text.trim(),
        dosage: _optionalFieldForSubmit(_dosage.text.trim(), isEdit: isEdit),
        frequency: _optionalFieldForSubmit(_frequency.text.trim(), isEdit: isEdit),
        duration: _optionalFieldForSubmit(_duration.text.trim(), isEdit: isEdit),
        notes: _optionalFieldForSubmit(_notes.text.trim(), isEdit: isEdit),
      ),
    );
  }
}
