import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/staff_form_dialog_fields.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';

class _StaffFormDialogCopy {
  const _StaffFormDialogCopy({
    required this.createTitle,
    required this.editTitle,
    required this.createDescription,
    required this.editDescription,
    required this.cancel,
    required this.createAccount,
    required this.saveChanges,
  });

  final String createTitle;
  final String editTitle;
  final String createDescription;
  final String editDescription;
  final String cancel;
  final String createAccount;
  final String saveChanges;
}

const _copyEn = _StaffFormDialogCopy(
  createTitle: 'Add staff member',
  editTitle: 'Edit staff member',
  createDescription: 'Create a sign-in account with a role and branch assignments.',
  editDescription: 'Update profile details, role, and branch access.',
  cancel: 'Cancel',
  createAccount: 'Create account',
  saveChanges: 'Save changes',
);

const _copyAr = _StaffFormDialogCopy(
  createTitle: 'إضافة موظف',
  editTitle: 'تعديل موظف',
  createDescription: 'إنشاء حساب تسجيل دخول مع دور وتعيينات فروع.',
  editDescription: 'تحديث تفاصيل الملف والدور وصلاحية الفروع.',
  cancel: 'إلغاء',
  createAccount: 'إنشاء حساب',
  saveChanges: 'حفظ التغييرات',
);

_StaffFormDialogCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Staff create/edit dialog (web `StaffFormDialog`).
class StaffFormDialog extends StatefulWidget {
  const StaffFormDialog({
    required this.open,
    required this.onOpenChange,
    required this.mode,
    required this.branches,
    required this.initialValues,
    required this.onSubmit,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final StaffFormMode mode;
  final List<BranchListItem> branches;
  final StaffFormValues initialValues;
  final ValueChanged<StaffFormValues> onSubmit;

  @override
  State<StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<StaffFormDialog> {
  late StaffFormValues _values = widget.initialValues;
  StaffFormErrors _errors = const {};

  @override
  void didUpdateWidget(covariant StaffFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && (!oldWidget.open || widget.initialValues != oldWidget.initialValues)) {
      _values = widget.initialValues;
      _errors = const {};
    }
  }

  void _handleSubmit() {
    final nextErrors = validateStaff(_values, widget.mode);
    if (nextErrors.isNotEmpty) {
      setState(() => _errors = nextErrors);
      return;
    }
    widget.onSubmit(_values);
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(Localizations.localeOf(context).languageCode);
    final isCreate = widget.mode == StaffFormMode.create;

    return AppDialog(
      open: widget.open,
      onOpenChange: widget.onOpenChange,
      size: AppDialogSize.lg,
      title: isCreate ? copy.createTitle : copy.editTitle,
      description: isCreate ? copy.createDescription : copy.editDescription,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            variant: AppButtonVariant.secondary,
            onPressed: () => widget.onOpenChange(false),
            child: Text(copy.cancel),
          ),
          const SizedBox(width: AppSpacing.space2),
          AppButton(
            onPressed: _handleSubmit,
            child: Text(isCreate ? copy.createAccount : copy.saveChanges),
          ),
        ],
      ),
      child: StaffFormDialogFields(
        mode: widget.mode,
        values: _values,
        onChanged: (values) => setState(() => _values = values),
        branches: widget.branches,
        errors: _errors,
      ),
    );
  }
}
