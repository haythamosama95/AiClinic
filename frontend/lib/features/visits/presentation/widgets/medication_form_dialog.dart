import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Dialog for creating or editing a patient current-medication record.
class MedicationFormDialog extends ConsumerStatefulWidget {
  const MedicationFormDialog({
    required this.open,
    required this.onOpenChange,
    required this.visitId,
    this.editing,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final String visitId;
  final PatientMedication? editing;

  @override
  ConsumerState<MedicationFormDialog> createState() => _MedicationFormDialogState();
}

class _MedicationFormDialogState extends ConsumerState<MedicationFormDialog> {
  late final TextEditingController _noteController;
  late final FocusNode _noteFocusNode;
  AppComboboxItem? _selectedMedication;
  String? _medicationError;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _noteFocusNode = FocusNode();
    _resetForm();
  }

  @override
  void didUpdateWidget(covariant MedicationFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && (!oldWidget.open || widget.editing != oldWidget.editing)) {
      _resetForm();
    }
  }

  void _resetForm() {
    final editing = widget.editing;
    _noteController.text = editing?.note ?? '';
    _medicationError = null;
    if (editing != null) {
      _selectedMedication = AppComboboxItem(id: editing.medicationId ?? editing.id, label: editing.name);
    } else {
      _selectedMedication = null;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  Future<List<AppComboboxItem>> _searchMedications(String query) async {
    final items = await ref.read(visitRepositoryProvider).searchMedications(query: query);
    return items.map((item) => AppComboboxItem(id: item.id, label: item.name)).toList(growable: false);
  }

  void _submit() {
    final medication = _selectedMedication;
    if (medication == null || medication.label.trim().isEmpty) {
      setState(() => _medicationError = 'Medication is required.');
      return;
    }

    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final note = _noteController.text.trim();
    final normalizedNote = note.isEmpty ? null : note;

    if (_isEditing) {
      notifier.stageUpdateMedication(
        medicationRecordId: widget.editing!.id,
        name: medication.label.trim(),
        medicationId: medication.id,
        note: normalizedNote,
      );
    } else {
      notifier.stageCreateMedication(
        name: medication.label.trim(),
        medicationId: medication.id,
        note: normalizedNote,
      );
    }
    widget.onOpenChange(false);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      open: widget.open,
      onOpenChange: widget.onOpenChange,
      size: AppDialogSize.sm,
      title: _isEditing ? 'Edit medication' : 'Add medication',
      description: 'Record a medication the patient is currently taking.',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            variant: AppButtonVariant.secondary,
            onPressed: () => widget.onOpenChange(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppSpacing.space2),
          AppButton(onPressed: _submit, child: Text(_isEditing ? 'Save changes' : 'Add medication')),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppFormField(
            id: 'medication-name',
            label: 'Medication',
            requiredMark: true,
            error: _medicationError,
            helperText: 'Search the medication catalog.',
            child: AppCombobox(
              id: 'medication-name',
              placeholder: 'Search medications…',
              value: _selectedMedication,
              invalid: _medicationError != null,
              onSearch: _searchMedications,
              onValueChange: (item) {
                setState(() {
                  _selectedMedication = item;
                  _medicationError = null;
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          AppFormField(
            id: 'medication-note',
            label: 'Note',
            helperText: 'Optional dosing or administration details.',
            child: Focus(
              focusNode: _noteFocusNode,
              child: AppTextInput(
                controller: _noteController,
                placeholder: 'e.g. 500 mg twice daily',
                id: 'medication-note',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
