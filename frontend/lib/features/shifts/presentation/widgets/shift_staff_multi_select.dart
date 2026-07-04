import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/shifts/domain/shift_branch_staff.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_branch_staff_provider.dart';

/// Multi-select of active staff assigned to the active branch (V1-7 US1).
class ShiftStaffMultiSelect extends ConsumerWidget {
  const ShiftStaffMultiSelect({
    required this.selectedStaffIds,
    required this.onChanged,
    this.enabled = true,
    this.excludeStaffIds = const {},
    super.key,
  });

  final Set<String> selectedStaffIds;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  final Set<String> excludeStaffIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchId = ref.watch(authSessionProvider.select((session) => session.context?.activeBranchId));

    ref.listen<String?>(authSessionProvider.select((session) => session.context?.activeBranchId), (previous, next) {
      if (previous != next && selectedStaffIds.isNotEmpty) {
        onChanged({});
      }
    });

    if (branchId == null || branchId.trim().isEmpty) {
      return AppAlert(
        variant: AppAlertVariant.warning,
        title: 'Select an active branch before assigning staff.',
      );
    }

    final staffAsync = ref.watch(shiftBranchStaffProvider(branchId));

    return staffAsync.when(
      loading: () => const AppFormField(
        label: 'Staff (optional)',
        child: Row(
          children: [
            AppSpinner(size: AppSpinnerSize.sm),
            SizedBox(width: AppSpacing.s3),
            Expanded(child: Text('Loading staff…', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppAlert(
            variant: AppAlertVariant.danger,
            title: 'Could not load staff for this branch.',
          ),
          const SizedBox(height: AppSpacing.s2),
          AppButton(
            label: 'Retry',
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            onPressed: () => ref.invalidate(shiftBranchStaffProvider(branchId)),
          ),
        ],
      ),
      data: (options) => _StaffOptionsList(
        options: options.where((option) => !excludeStaffIds.contains(option.id)).toList(growable: false),
        selectedStaffIds: selectedStaffIds,
        enabled: enabled,
        onChanged: onChanged,
      ),
    );
  }
}

class _StaffOptionsList extends StatelessWidget {
  const _StaffOptionsList({
    required this.options,
    required this.selectedStaffIds,
    required this.enabled,
    required this.onChanged,
  });

  final List<ShiftBranchStaffMember> options;
  final Set<String> selectedStaffIds;
  final bool enabled;
  final ValueChanged<Set<String>> onChanged;

  void _toggleStaff(String staffId, bool selected) {
    final next = Set<String>.from(selectedStaffIds);
    if (selected) {
      next.add(staffId);
    } else {
      next.remove(staffId);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    if (options.isEmpty) {
      return const AppFormField(
        label: 'Staff (optional)',
        child: Text('No active staff are assigned to this branch. You can save an unassigned shift.'),
      );
    }

    return Column(
      key: const Key('shift_staff_multi_select'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Staff (optional)', style: typography.bodyStrong.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.s3),
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCheckbox(
                  key: Key('shift_staff_option_${option.id}'),
                  value: selectedStaffIds.contains(option.id),
                  disabled: !enabled,
                  onChanged: enabled ? (checked) => _toggleStaff(option.id, checked ?? false) : null,
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.fullName, style: typography.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        option.role.wireValue.replaceAll('_', ' '),
                        style: typography.caption.copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
