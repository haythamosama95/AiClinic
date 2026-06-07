import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Select an active branch before assigning staff.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      );
    }

    final staffAsync = ref.watch(shiftBranchStaffProvider(branchId));

    return staffAsync.when(
      loading: () => const InputDecorator(
        decoration: InputDecoration(labelText: 'Staff (optional)'),
        child: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Loading staff…'),
          ],
        ),
      ),
      error: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Could not load staff for this branch.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: () => ref.invalidate(shiftBranchStaffProvider(branchId)), child: const Text('Retry')),
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
    if (options.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'Staff (optional)'),
        child: Text('No active staff are assigned to this branch. You can save an unassigned shift.'),
      );
    }

    return Column(
      key: const Key('shift_staff_multi_select'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Staff (optional)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final option in options)
          CheckboxListTile(
            key: Key('shift_staff_option_${option.id}'),
            value: selectedStaffIds.contains(option.id),
            enabled: enabled,
            title: Text(option.fullName),
            subtitle: Text(option.role.wireValue.replaceAll('_', ' ')),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: enabled ? (checked) => _toggleStaff(option.id, checked ?? false) : null,
          ),
      ],
    );
  }
}
