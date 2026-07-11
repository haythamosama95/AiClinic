import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/presentation/forms/branch_form_fields.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/branch_form_values.dart';

enum BranchFormDialogMode { create, edit }

/// Create/edit branch dialog (web `BranchFormDialog`).
class BranchFormDialog extends StatefulWidget {
  const BranchFormDialog({
    required this.open,
    required this.onOpenChange,
    required this.mode,
    required this.initialValues,
    required this.onSubmit,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final BranchFormDialogMode mode;
  final BranchFormValues initialValues;
  final ValueChanged<BranchFormValues> onSubmit;

  @override
  State<BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<BranchFormDialog> {
  late BranchFormValues _values = widget.initialValues;
  BranchFormErrors _errors = const {};

  @override
  void didUpdateWidget(covariant BranchFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && (!oldWidget.open || widget.initialValues != oldWidget.initialValues)) {
      _values = widget.initialValues;
      _errors = const {};
    }
  }

  void _handleSubmit() {
    final nextErrors = validateBranch(_values, requireHours: widget.mode == BranchFormDialogMode.create);
    if (nextErrors.isNotEmpty) {
      setState(() => _errors = nextErrors);
      return;
    }
    widget.onSubmit(_values);
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.mode == BranchFormDialogMode.create;

    return AppDialog(
      open: widget.open,
      onOpenChange: widget.onOpenChange,
      title: isCreate ? 'Add branch' : 'Edit branch',
      description: isCreate
          ? 'Start with your main branch. Additional branches can be added later.'
          : 'Update location details and working hours for this branch.',
      size: AppDialogSize.lg,
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            variant: AppButtonVariant.secondary,
            onPressed: () => widget.onOpenChange(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppSpacing.space2),
          AppButton(
            onPressed: _handleSubmit,
            child: Text(isCreate ? 'Create branch' : 'Save changes'),
          ),
        ],
      ),
      child: BranchFormFields(
        values: _values,
        errors: _errors,
        onChanged: (values) => setState(() => _values = values),
      ),
    );
  }
}
