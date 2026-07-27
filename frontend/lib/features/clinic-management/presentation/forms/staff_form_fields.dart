import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/constants/clinic_constants.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';

class StaffFormFields extends StatelessWidget {
  const StaffFormFields({
    required this.mode,
    required this.values,
    required this.onChanged,
    required this.branches,
    this.disabled = false,
    this.errors = const {},
    super.key,
  });

  final StaffFormMode mode;
  final StaffFormValues values;
  final ValueChanged<StaffFormValues> onChanged;
  final List<BranchListItem> branches;
  final bool disabled;
  final StaffFormErrors errors;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final activeBranches = branches.where((branch) => branch.isActive).toList();
    final branchOptions = [
      for (final branch in activeBranches)
        AppComboboxItem(
          id: branch.id,
          label: branch.code == null || branch.code!.isEmpty ? branch.name : '${branch.name} (${branch.code})',
        ),
    ];
    final selectedBranches = branchOptions.where((option) => values.branchIds.contains(option.id)).toList();
    final primaryOptions = [
      for (final option in selectedBranches) AppSelectOption(value: option.id, label: option.label),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: AppSpacing.space5,
          runSpacing: AppSpacing.space5,
          children: [
            SizedBox(
              width: 280,
              child: AppFormField(
                id: 'staff-name',
                label: 'Full name',
                requiredMark: true,
                error: errors['fullName'],
                child: AppTextInput(
                  id: 'staff-name',
                  initialValue: values.fullName,
                  onChanged: (next) => onChanged(values.copyWith(fullName: next)),
                  placeholder: 'Enter full name',
                  disabled: disabled,
                  readOnly: disabled,
                  invalid: errors.containsKey('fullName'),
                ),
              ),
            ),
            SizedBox(
              width: 280,
              child: AppFormField(
                id: 'staff-phone',
                label: mode == StaffFormMode.create ? 'Phone number' : 'Phone',
                requiredMark: mode == StaffFormMode.create,
                error: errors['phone'],
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: AppTextInput(
                    id: 'staff-phone',
                    initialValue: values.phone,
                    onChanged: (next) => onChanged(values.copyWith(phone: next.replaceAll(RegExp(r'\D'), ''))),
                    placeholder: 'Numbers only',
                    disabled: disabled,
                    readOnly: disabled,
                    invalid: errors.containsKey('phone'),
                  ),
                ),
              ),
            ),
            if (mode == StaffFormMode.create) ...[
              SizedBox(
                width: 280,
                child: AppFormField(
                  id: 'staff-username',
                  label: 'Username',
                  requiredMark: true,
                  hint: kUsernameHint,
                  error: errors['username'],
                  child: AppTextInput(
                    id: 'staff-username',
                    initialValue: values.username,
                    onChanged: (next) => onChanged(values.copyWith(username: next)),
                    placeholder: 'Staff username',
                    disabled: disabled,
                    readOnly: disabled,
                    invalid: errors.containsKey('username'),
                  ),
                ),
              ),
              SizedBox(
                width: 280,
                child: AppFormField(
                  id: 'staff-password',
                  label: 'Initial password',
                  requiredMark: true,
                  hint: '$kPasswordHint Shown once after creation so you can share it with the staff member.',
                  error: errors['password'],
                  child: AppPasswordInput(
                    id: 'staff-password',
                    initialValue: values.password,
                    onChanged: (next) => onChanged(values.copyWith(password: next)),
                    placeholder: '••••••••',
                    disabled: disabled,
                    readOnly: disabled,
                    invalid: errors.containsKey('password'),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.space5),
        Wrap(
          spacing: AppSpacing.space5,
          runSpacing: AppSpacing.space5,
          children: [
            SizedBox(
              width: 280,
              child: AppFormField(
                id: 'staff-role',
                label: 'Role',
                requiredMark: true,
                error: errors['role'],
                child: AppSelect(
                  value: values.role?.wireValue,
                  options: [
                    for (final role in kStaffRoles)
                      AppSelectOption(value: role.value.wireValue, label: role.label),
                  ],
                  placeholder: 'Select a role',
                  disabled: disabled,
                  readOnly: disabled,
                  invalid: errors.containsKey('role'),
                  onChanged: (next) => onChanged(values.copyWith(role: StaffRole.tryParse(next))),
                ),
              ),
            ),
            SizedBox(
              width: 280,
              child: AppFormField(
                id: 'staff-branches',
                label: 'Branch assignments',
                requiredMark: true,
                error: errors['branchIds'],
                child: activeBranches.isEmpty
                    ? Text(
                        'No active branches are available. Create or reactivate a branch first.',
                        style: AppTypography.bodySm(context),
                      )
                    : AppMultiSelect(
                        value: selectedBranches,
                        options: branchOptions,
                        placeholder: 'Select branches',
                        disabled: disabled,
                        invalid: errors.containsKey('branchIds'),
                        onValueChange: (items) {
                          final ids = items.map((item) => item.id).toList();
                          final primaryStillValid =
                              values.primaryBranchId != null && ids.contains(values.primaryBranchId);
                          onChanged(
                            values.copyWith(
                              branchIds: ids,
                              primaryBranchId: primaryStillValid ? values.primaryBranchId : (ids.isEmpty ? null : ids.first),
                              clearPrimaryBranchId: ids.isEmpty,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
        if (values.branchIds.length > 1) ...[
          const SizedBox(height: AppSpacing.space5),
          SizedBox(
            width: 280,
            child: AppFormField(
              id: 'staff-primary',
              label: 'Primary branch',
              child: AppSelect(
                value: values.primaryBranchId,
                options: primaryOptions,
                disabled: disabled,
                readOnly: disabled,
                onChanged: (next) => onChanged(values.copyWith(primaryBranchId: next)),
              ),
            ),
          ),
        ],
        if (mode == StaffFormMode.edit) ...[
          const SizedBox(height: AppSpacing.space5),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceSunken.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Login credentials', style: AppTypography.bodyStrong(context)),
                  const SizedBox(height: AppSpacing.space4),
                  Wrap(
                    spacing: AppSpacing.space5,
                    runSpacing: AppSpacing.space5,
                    children: [
                      SizedBox(
                        width: 280,
                        child: AppFormField(
                          id: 'staff-username-edit',
                          label: 'Username',
                          requiredMark: true,
                          hint: kUsernameHint,
                          error: errors['username'],
                          child: AppTextInput(
                            id: 'staff-username-edit',
                            initialValue: values.username,
                            onChanged: (next) => onChanged(values.copyWith(username: next)),
                            placeholder: 'Staff username',
                            disabled: disabled,
                            readOnly: disabled,
                            invalid: errors.containsKey('username'),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 280,
                        child: AppFormField(
                          id: 'staff-password-edit',
                          label: 'New password',
                          hint: '$kPasswordHint Leave blank to keep the current password.',
                          error: errors['password'],
                          child: AppPasswordInput(
                            id: 'staff-password-edit',
                            initialValue: values.password,
                            onChanged: (next) => onChanged(values.copyWith(password: next)),
                            placeholder: '••••••••',
                            disabled: disabled,
                            readOnly: disabled,
                            invalid: errors.containsKey('password'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
