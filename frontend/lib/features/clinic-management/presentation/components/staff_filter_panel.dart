import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/filter_menu_panel.dart';
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

  List<FilterMenuOption> _toFilterOptions(List<AppSelectOption> options) {
    return [for (final option in options) FilterMenuOption(value: option.value, label: option.label)];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasActiveFilters = role != null || (branchId != null && branchId!.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Filters', style: AppTypography.title(context)),
          const SizedBox(height: AppSpacing.space3),
          SizedBox(
            height: 1,
            child: ColoredBox(color: colors.borderSubtle),
          ),
          const SizedBox(height: AppSpacing.space3),
          FilterMenuPanel(
            sections: [
              FilterMenuSection(
                id: 'role',
                label: 'Role',
                value: role?.wireValue ?? 'all',
                options: _toFilterOptions(roleOptions),
                onChange: (next) => onRoleChange(next == 'all' ? null : StaffRole.tryParse(next)),
              ),
              FilterMenuSection(
                id: 'branch',
                label: 'Branch',
                value: branchId ?? 'all',
                options: _toFilterOptions(branchOptions),
                onChange: (next) => onBranchChange(next == 'all' ? null : next),
              ),
            ],
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
      ),
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
