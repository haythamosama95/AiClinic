import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Dialog for creating or editing a patient chronic condition record.
class ConditionFormDialog extends ConsumerStatefulWidget {
  const ConditionFormDialog({
    required this.open,
    required this.onOpenChange,
    required this.visitId,
    this.editing,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final String visitId;
  final PatientChronicCondition? editing;

  @override
  ConsumerState<ConditionFormDialog> createState() => _ConditionFormDialogState();
}

class _ConditionFormDialogState extends ConsumerState<ConditionFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late final FocusNode _nameFocusNode;
  late final FocusNode _noteFocusNode;
  String? _nameError;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _noteController = TextEditingController();
    _nameFocusNode = FocusNode();
    _noteFocusNode = FocusNode();
    _resetForm();
  }

  @override
  void didUpdateWidget(covariant ConditionFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && (!oldWidget.open || widget.editing != oldWidget.editing)) {
      _resetForm();
    }
  }

  void _resetForm() {
    final editing = widget.editing;
    _nameController.text = editing?.name ?? '';
    _noteController.text = editing?.note ?? '';
    _nameError = null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _nameFocusNode.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Condition name is required.');
      return;
    }

    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final note = _noteController.text.trim();
    final normalizedNote = note.isEmpty ? null : note;

    if (_isEditing) {
      notifier.stageUpdateCondition(conditionId: widget.editing!.id, name: name, note: normalizedNote);
    } else {
      notifier.stageCreateCondition(name: name, note: normalizedNote);
    }
    widget.onOpenChange(false);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      open: widget.open,
      onOpenChange: widget.onOpenChange,
      size: AppDialogSize.sm,
      title: _isEditing ? 'Edit condition' : 'Add condition',
      description: 'Record an active diagnosis or long-term condition.',
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
          AppButton(onPressed: _submit, child: Text(_isEditing ? 'Save changes' : 'Add condition')),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppFormField(
            id: 'condition-name',
            label: 'Condition',
            requiredMark: true,
            error: _nameError,
            child: Focus(
              focusNode: _nameFocusNode,
              child: AppTextInput(
                controller: _nameController,
                placeholder: 'e.g. Type 2 diabetes',
                id: 'condition-name',
                invalid: _nameError != null,
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          AppFormField(
            id: 'condition-note',
            label: 'Note',
            helperText: 'Optional clinical context.',
            child: Focus(
              focusNode: _noteFocusNode,
              child: AppTextInput(
                controller: _noteController,
                placeholder: 'e.g. Diagnosed 2019, well controlled',
                id: 'condition-note',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
