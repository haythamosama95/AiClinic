import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';

/// Result from [InvestigationFormDialog.show].
class InvestigationFormResult {
  const InvestigationFormResult({required this.name, this.note, this.investigationId});

  final String name;
  final String? note;
  final String? investigationId;
}

/// Dialog for ordering or editing an investigation line.
class InvestigationFormDialog extends ConsumerStatefulWidget {
  const InvestigationFormDialog({required this.usedInvestigationIds, this.editingEntry, super.key});

  final Set<String> usedInvestigationIds;
  final VisitInvestigation? editingEntry;

  static Future<InvestigationFormResult?> show(
    BuildContext context, {
    required Set<String> usedInvestigationIds,
    VisitInvestigation? editingEntry,
  }) {
    final isEditing = editingEntry != null;
    return AppDialog.show<InvestigationFormResult>(
      context,
      title: isEditing ? 'Edit investigation' : 'Add investigation',
      description: isEditing
          ? 'Update the test or add clinical context for this order.'
          : 'Choose a diagnostic test and add any relevant clinical notes.',
      size: AppDialogSize.md,
      child: InvestigationFormDialog(usedInvestigationIds: usedInvestigationIds, editingEntry: editingEntry),
    );
  }

  @override
  ConsumerState<InvestigationFormDialog> createState() => _InvestigationFormDialogState();
}

class _InvestigationFormDialogState extends ConsumerState<InvestigationFormDialog> {
  late final TextEditingController _noteController;
  AppComboboxItem? _selectedInvestigation;
  String? _investigationError;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.editingEntry?.note ?? '');
    final editingId = widget.editingEntry?.investigationId;
    if (editingId != null && editingId.isNotEmpty) {
      _selectedInvestigation = AppComboboxItem(id: editingId, label: widget.editingEntry!.name);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<List<AppComboboxItem>> _searchInvestigations(String query) async {
    try {
      final items = await ref.read(visitRepositoryProvider).searchInvestigations(query: query);
      return [
        for (final item in items)
          AppComboboxItem(
            id: item.id,
            label: item.name,
            meta: item.defaultUnit,
            disabled: widget.usedInvestigationIds.contains(item.id) && item.id != widget.editingEntry?.investigationId,
            disabledReason: 'Already added',
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  void _submit() {
    final selected = _selectedInvestigation;
    if (selected == null) {
      setState(() => _investigationError = 'Select an investigation.');
      return;
    }

    Navigator.of(context).pop(
      InvestigationFormResult(
        name: selected.label,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        investigationId: selected.id,
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
          id: 'investigation-type',
          label: 'Investigation',
          requiredMark: true,
          error: _investigationError,
          child: AppCombobox(
            id: 'investigation-type',
            placeholder: 'Search labs, imaging, and tests…',
            value: _selectedInvestigation,
            invalid: _investigationError != null,
            onValueChange: (item) {
              setState(() {
                _selectedInvestigation = item;
                _investigationError = null;
              });
            },
            onSearch: _searchInvestigations,
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        AppFormField(
          id: 'investigation-note',
          label: 'Clinical note',
          hint: 'Urgency, indication, or instructions for the lab or imaging team.',
          child: AppTextarea(
            controller: _noteController,
            placeholder: 'e.g. Fasting sample · rule out infection…',
            rows: 3,
            autoGrow: true,
          ),
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
              leadingIcon: const Icon(Icons.science_outlined, size: 16),
              onPressed: _submit,
              child: Text(_isEditing ? 'Save changes' : 'Add investigation'),
            ),
          ],
        ),
      ],
    );
  }
}
