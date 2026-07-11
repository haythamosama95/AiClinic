import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/presentation/constants/clinic_constants.dart';

class StaffFilterPanel extends StatelessWidget {
  const StaffFilterPanel({
    required this.role,
    required this.branchId,
    required this.roleOptions,
    required this.branchOptions,
    required this.onRoleChange,
    required this.onBranchChange,
    required this.onClearAll,
    super.key,
  });

  final StaffRole? role;
  final String? branchId;
  final List<AppSelectOption> roleOptions;
  final List<AppSelectOption> branchOptions;
  final ValueChanged<StaffRole?> onRoleChange;
  final ValueChanged<String?> onBranchChange;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasActiveFilters = role != null || (branchId != null && branchId!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Filters', style: AppTypography.overline(context)),
        const SizedBox(height: AppSpacing.space3),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceSunken.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppFormField(
                  id: 'staff-filter-role',
                  label: 'Role',
                  child: AppSelect(
                    value: role?.wireValue ?? 'all',
                    options: roleOptions,
                    onChanged: (next) => onRoleChange(next == 'all' ? null : StaffRole.tryParse(next)),
                  ),
                ),
                const SizedBox(height: AppSpacing.space3),
                AppFormField(
                  id: 'staff-filter-branch',
                  label: 'Branch',
                  child: AppSelect(
                    value: branchId ?? 'all',
                    options: branchOptions,
                    onChanged: (next) => onBranchChange(next == 'all' ? null : next),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasActiveFilters) ...[
          const SizedBox(height: AppSpacing.space4),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: onClearAll,
              child: const Text('Clear filters'),
            ),
          ),
        ],
      ],
    );
  }
}

List<AppSelectOption> staffRoleFilterOptions() => [
  const AppSelectOption(value: 'all', label: 'All roles'),
  for (final role in kStaffRoles) AppSelectOption(value: role.value.wireValue, label: role.label),
];

List<AppSelectOption> staffBranchFilterOptions(List<({String id, String label})> branches) => [
  const AppSelectOption(value: 'all', label: 'All branches'),
  for (final branch in branches) AppSelectOption(value: branch.id, label: branch.label),
];
