import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Result from [MedicalBackgroundFormDialog.show].
class MedicalBackgroundFormResult {
  const MedicalBackgroundFormResult({required this.title, this.note});

  final String title;
  final String? note;
}

/// Dialog for adding or editing a medical-background item with an optional note.
class MedicalBackgroundFormDialog extends StatefulWidget {
  const MedicalBackgroundFormDialog({
    required this.dialogTitle,
    required this.dialogDescription,
    required this.itemLabel,
    required this.noteLabel,
    required this.itemPlaceholder,
    required this.notePlaceholder,
    this.initialTitle,
    this.initialNote,
    super.key,
  });

  final String dialogTitle;
  final String dialogDescription;
  final String itemLabel;
  final String noteLabel;
  final String itemPlaceholder;
  final String notePlaceholder;
  final String? initialTitle;
  final String? initialNote;

  static Future<MedicalBackgroundFormResult?> show(
    BuildContext context, {
    required String dialogTitle,
    required String dialogDescription,
    required String itemLabel,
    required String noteLabel,
    required String itemPlaceholder,
    required String notePlaceholder,
    String? initialTitle,
    String? initialNote,
  }) {
    return AppDialog.show<MedicalBackgroundFormResult>(
      context,
      title: dialogTitle,
      description: dialogDescription,
      size: AppDialogSize.sm,
      child: MedicalBackgroundFormDialog(
        dialogTitle: dialogTitle,
        dialogDescription: dialogDescription,
        itemLabel: itemLabel,
        noteLabel: noteLabel,
        itemPlaceholder: itemPlaceholder,
        notePlaceholder: notePlaceholder,
        initialTitle: initialTitle,
        initialNote: initialNote,
      ),
    );
  }

  @override
  State<MedicalBackgroundFormDialog> createState() => _MedicalBackgroundFormDialogState();
}

class _MedicalBackgroundFormDialogState extends State<MedicalBackgroundFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _noteController = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Enter a name to continue.');
      return;
    }

    final note = _noteController.text.trim();
    Navigator.of(context).pop(MedicalBackgroundFormResult(title: title, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialTitle != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFormField(
          id: 'medical-background-item',
          label: widget.itemLabel,
          requiredMark: true,
          error: _titleError,
          child: AppTextInput(
            controller: _titleController,
            placeholder: widget.itemPlaceholder,
            invalid: _titleError != null,
            onChanged: (_) {
              if (_titleError != null) {
                setState(() => _titleError = null);
              }
            },
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        AppFormField(
          id: 'medical-background-note',
          label: widget.noteLabel,
          helperText: 'Optional',
          child: AppTextarea(controller: _noteController, placeholder: widget.notePlaceholder, rows: 3, autoGrow: true),
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
            AppButton(onPressed: _submit, child: Text(isEditing ? 'Save changes' : 'Add')),
          ],
        ),
      ],
    );
  }
}
