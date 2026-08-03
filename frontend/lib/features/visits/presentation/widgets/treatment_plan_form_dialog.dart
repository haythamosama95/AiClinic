import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_options.dart';

/// Result from [TreatmentPlanFormDialog.show].
class TreatmentPlanFormResult {
  const TreatmentPlanFormResult({
    required this.medicationName,
    this.medicationId,
    required this.dosage,
    required this.frequency,
    required this.duration,
  });

  final String medicationName;
  final String? medicationId;
  final String dosage;
  final String frequency;
  final String duration;
}

/// Dialog for adding or editing a prescription line.
class TreatmentPlanFormDialog extends ConsumerStatefulWidget {
  const TreatmentPlanFormDialog({this.editingEntry, super.key});

  final TreatmentPlanItem? editingEntry;

  static Future<TreatmentPlanFormResult?> show(BuildContext context, {TreatmentPlanItem? editingEntry}) {
    final isEditing = editingEntry != null;
    return AppDialog.show<TreatmentPlanFormResult>(
      context,
      title: isEditing ? 'Edit prescription' : 'Add prescription',
      description: isEditing
          ? 'Update medication, dosage, frequency, or duration.'
          : 'Prescribe a medication with dosage, frequency, and duration.',
      size: AppDialogSize.md,
      child: TreatmentPlanFormDialog(editingEntry: editingEntry),
    );
  }

  @override
  ConsumerState<TreatmentPlanFormDialog> createState() => _TreatmentPlanFormDialogState();
}

class _TreatmentPlanFormDialogState extends ConsumerState<TreatmentPlanFormDialog> {
  late final TextEditingController _dosageController;
  AppComboboxItem? _selectedMedication;
  String? _frequency;
  String? _duration;
  String? _medicationError;
  String? _dosageError;
  String? _frequencyError;
  String? _durationError;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.editingEntry;
    _dosageController = TextEditingController(text: entry?.dosage ?? '');
    _frequency = entry?.frequency;
    _duration = entry?.duration;
    if (entry != null) {
      _selectedMedication = AppComboboxItem(
        id: entry.medicationId ?? entry.medicationName,
        label: entry.medicationName,
      );
    }
  }

  @override
  void dispose() {
    _dosageController.dispose();
    super.dispose();
  }

  Future<List<AppComboboxItem>> _searchMedications(String query) async {
    try {
      final items = await ref.read(visitRepositoryProvider).searchMedications(query: query);
      return [for (final item in items) AppComboboxItem(id: item.id, label: item.name)];
    } catch (_) {
      return [];
    }
  }

  void _submit() {
    final selected = _selectedMedication;
    final dosage = _dosageController.text.trim();
    String? medicationError;
    String? dosageError;
    String? frequencyError;
    String? durationError;

    if (selected == null) {
      medicationError = 'Select a medication.';
    }
    if (dosage.isEmpty) {
      dosageError = 'Enter the dosage.';
    }
    if (_frequency == null || _frequency!.isEmpty) {
      frequencyError = 'Select a frequency.';
    }
    if (_duration == null || _duration!.isEmpty) {
      durationError = 'Select a duration.';
    }

    if (medicationError != null || dosageError != null || frequencyError != null || durationError != null) {
      setState(() {
        _medicationError = medicationError;
        _dosageError = dosageError;
        _frequencyError = frequencyError;
        _durationError = durationError;
      });
      return;
    }

    final medicationId = selected!.id;
    final isCatalogId = medicationId != selected.label;

    Navigator.of(context).pop(
      TreatmentPlanFormResult(
        medicationName: selected.label,
        medicationId: isCatalogId ? medicationId : null,
        dosage: dosage,
        frequency: _frequency!,
        duration: _duration!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFormField(
          id: 'treatment-medication',
          label: 'Medication',
          requiredMark: true,
          error: _medicationError,
          child: AppCombobox(
            id: 'treatment-medication',
            placeholder: 'Search medications…',
            value: _selectedMedication,
            invalid: _medicationError != null,
            onValueChange: (item) {
              setState(() {
                _selectedMedication = item;
                _medicationError = null;
              });
            },
            onSearch: _searchMedications,
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 480;
            final dosageField = AppFormField(
              id: 'treatment-dosage',
              label: 'Dosage',
              requiredMark: true,
              error: _dosageError,
              child: AppTextInput(
                id: 'treatment-dosage',
                controller: _dosageController,
                placeholder: 'e.g. 500 mg',
                invalid: _dosageError != null,
                onChanged: (_) {
                  if (_dosageError != null) {
                    setState(() => _dosageError = null);
                  }
                },
              ),
            );
            final frequencyField = AppFormField(
              id: 'treatment-frequency',
              label: 'Frequency',
              requiredMark: true,
              error: _frequencyError,
              child: AppSelect(
                id: 'treatment-frequency-select',
                value: _frequency,
                placeholder: 'Select frequency',
                invalid: _frequencyError != null,
                options: treatmentFrequencyOptions,
                onChanged: (value) {
                  setState(() {
                    _frequency = value;
                    _frequencyError = null;
                  });
                },
              ),
            );
            final durationField = AppFormField(
              id: 'treatment-duration',
              label: 'Duration',
              requiredMark: true,
              error: _durationError,
              child: AppSelect(
                id: 'treatment-duration-select',
                value: _duration,
                placeholder: 'Select duration',
                invalid: _durationError != null,
                options: treatmentDurationOptions,
                onChanged: (value) {
                  setState(() {
                    _duration = value;
                    _durationError = null;
                  });
                },
              ),
            );

            if (!isWide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dosageField,
                  const SizedBox(height: AppSpacing.space4),
                  frequencyField,
                  const SizedBox(height: AppSpacing.space4),
                  durationField,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: dosageField),
                    const SizedBox(width: AppSpacing.space4),
                    Expanded(child: frequencyField),
                  ],
                ),
                const SizedBox(height: AppSpacing.space4),
                durationField,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.space5),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              leadingIcon: const Icon(Icons.medication_outlined, size: 16),
              onPressed: _submit,
              child: Text(_isEditing ? 'Save changes' : 'Add prescription'),
            ),
          ],
        ),
      ],
    );
  }
}
