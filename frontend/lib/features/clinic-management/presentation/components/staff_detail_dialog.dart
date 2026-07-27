import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/staff_form_dialog_fields.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';

class _StaffDetailDialogCopy {
  const _StaffDetailDialogCopy({
    required this.description,
    required this.close,
    required this.edit,
    required this.delete,
  });

  final String description;
  final String close;
  final String edit;
  final String delete;
}

const _copyEn = _StaffDetailDialogCopy(
  description: 'Profile details, role, and branch access.',
  close: 'Close',
  edit: 'Edit',
  delete: 'Delete',
);

const _copyAr = _StaffDetailDialogCopy(
  description: 'تفاصيل الملف والدور وصلاحية الفروع.',
  close: 'إغلاق',
  edit: 'تعديل',
  delete: 'حذف',
);

_StaffDetailDialogCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Read-only staff detail dialog with Edit and Delete actions.
class StaffDetailDialog extends StatelessWidget {
  const StaffDetailDialog({
    required this.open,
    required this.onOpenChange,
    required this.member,
    required this.branches,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final StaffListItem member;
  final List<BranchListItem> branches;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(Localizations.localeOf(context).languageCode);

    return AppDialog(
      open: open,
      onOpenChange: onOpenChange,
      size: AppDialogSize.lg,
      title: member.fullName,
      description: copy.description,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            variant: AppButtonVariant.danger,
            leadingIcon: const Icon(Icons.delete_outline, size: 16),
            onPressed: () {
              onOpenChange(false);
              onDelete();
            },
            child: Text(copy.delete),
          ),
          const SizedBox(width: AppSpacing.space2),
          AppButton(variant: AppButtonVariant.secondary, onPressed: () => onOpenChange(false), child: Text(copy.close)),
          const SizedBox(width: AppSpacing.space2),
          AppButton(
            leadingIcon: const Icon(Icons.edit, size: 16),
            onPressed: () {
              onOpenChange(false);
              onEdit();
            },
            child: Text(copy.edit),
          ),
        ],
      ),
      child: StaffFormDialogFields(
        mode: StaffFormMode.edit,
        values: staffToFormValues(member),
        onChanged: (_) {},
        branches: branches,
        disabled: true,
      ),
    );
  }
}
