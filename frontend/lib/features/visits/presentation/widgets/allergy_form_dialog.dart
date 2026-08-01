import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Dialog for creating or editing a patient allergy record.
class AllergyFormDialog extends ConsumerStatefulWidget {
  const AllergyFormDialog({
    required this.open,
    required this.onOpenChange,
    required this.visitId,
    this.editing,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final String visitId;
  final PatientAllergy? editing;

  @override
  ConsumerState<AllergyFormDialog> createState() => _AllergyFormDialogState();
}

class _AllergyFormDialogState extends ConsumerState<AllergyFormDialog> {
  late final TextEditingController _substanceController;
  late final FocusNode _substanceFocusNode;
  String? _reaction;
  String? _substanceError;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _substanceController = TextEditingController();
    _substanceFocusNode = FocusNode();
    _resetForm();
  }

  @override
  void didUpdateWidget(covariant AllergyFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && (!oldWidget.open || widget.editing != oldWidget.editing)) {
      _resetForm();
    }
  }

  void _resetForm() {
    final editing = widget.editing;
    _substanceController.text = editing?.substance ?? '';
    _reaction = editing?.reaction;
    _substanceError = null;
  }

  @override
  void dispose() {
    _substanceController.dispose();
    _substanceFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final substance = _substanceController.text.trim();
    if (substance.isEmpty) {
      setState(() => _substanceError = 'Substance is required.');
      return;
    }

    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    if (_isEditing) {
      notifier.stageUpdateAllergy(
        allergyId: widget.editing!.id,
        substance: substance,
        reaction: _reaction,
      );
    } else {
      notifier.stageCreateAllergy(substance: substance, reaction: _reaction);
    }
    widget.onOpenChange(false);
  }

  @override
  Widget build(BuildContext context) {
    final reactionOptions = AllergySeverityOptions.items.entries
        .map((entry) => AppSelectOption(value: entry.key, label: entry.value))
        .toList(growable: false);

    return AppDialog(
      open: widget.open,
      onOpenChange: widget.onOpenChange,
      size: AppDialogSize.sm,
      title: _isEditing ? 'Edit allergy' : 'Add allergy',
      description: 'Record a drug, food, or environmental allergy.',
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
          AppButton(onPressed: _submit, child: Text(_isEditing ? 'Save changes' : 'Add allergy')),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppFormField(
            id: 'allergy-substance',
            label: 'Substance',
            requiredMark: true,
            error: _substanceError,
            child: Focus(
              focusNode: _substanceFocusNode,
              child: AppTextInput(
                controller: _substanceController,
                placeholder: 'e.g. Penicillin',
                id: 'allergy-substance',
                invalid: _substanceError != null,
                onChanged: (_) {
                  if (_substanceError != null) {
                    setState(() => _substanceError = null);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          AppFormField(
            id: 'allergy-reaction',
            label: 'Severity',
            helperText: 'Optional reaction severity.',
            child: AppSelect(
              id: 'allergy-reaction',
              options: reactionOptions,
              value: _reaction ?? '',
              placeholder: 'Select severity',
              onChanged: (value) => setState(() => _reaction = value.isEmpty ? null : value),
            ),
          ),
        ],
      ),
    );
  }
}
