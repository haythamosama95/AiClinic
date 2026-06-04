import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final subtitleParts = TreatmentPlanDisplay.subtitleParts(plan);

    return Card(
      key: Key('treatment_plan_card_${plan.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(plan.medicationName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitleParts.isNotEmpty) Text(subtitleParts.join(' · ')),
            if (plan.notes != null && plan.notes!.isNotEmpty)
              Text(plan.notes!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: canEdit
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('treatment_plan_edit_${plan.id}'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    key: Key('treatment_plan_archive_${plan.id}'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onArchive,
                    tooltip: 'Remove',
                  ),
                ],
              )
            : null,
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

  /// RPC params for [VisitRepository.updateTreatmentPlan] — only fields changed from [existing].
  ///
  /// Optional text uses backend semantics: omitted = keep, `''` = clear. Legacy [TreatmentPlanItem.startDate]
  /// / [TreatmentPlanItem.endDate] are never sent (no UI to edit or clear them).
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit treatment plan' : 'New treatment plan',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('treatment_plan_medication_field'),
                controller: _medication,
                decoration: const InputDecoration(labelText: 'Medication name *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                enabled: !widget.isSubmitting,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('treatment_plan_dosage_field'),
                      controller: _dosage,
                      decoration: const InputDecoration(labelText: 'Dosage', border: OutlineInputBorder()),
                      enabled: !widget.isSubmitting,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: const Key('treatment_plan_frequency_field'),
                      controller: _frequency,
                      decoration: const InputDecoration(labelText: 'Frequency', border: OutlineInputBorder()),
                      enabled: !widget.isSubmitting,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('treatment_plan_duration_field'),
                controller: _duration,
                decoration: const InputDecoration(
                  labelText: 'Duration',
                  hintText: 'e.g. 7 days, 2 weeks',
                  border: OutlineInputBorder(),
                ),
                enabled: !widget.isSubmitting,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('treatment_plan_notes_field'),
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                minLines: 1,
                maxLines: 3,
                enabled: !widget.isSubmitting,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('treatment_plan_cancel_button'),
                    onPressed: widget.isSubmitting ? null : widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('treatment_plan_save_button'),
                    onPressed: widget.isSubmitting ? null : _submit,
                    child: widget.isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isEdit ? 'Update' : 'Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// On edit, empty optional fields send `''` so the backend can clear them (NULL = keep).
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
