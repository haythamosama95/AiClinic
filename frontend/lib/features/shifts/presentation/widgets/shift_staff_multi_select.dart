import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Multi-select of active staff assigned to the active branch (V1-7 US1).
class ShiftStaffMultiSelect extends ConsumerStatefulWidget {
  const ShiftStaffMultiSelect({
    required this.selectedStaffIds,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final Set<String> selectedStaffIds;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  @override
  ConsumerState<ShiftStaffMultiSelect> createState() => _ShiftStaffMultiSelectState();
}

class _BranchStaffOption {
  const _BranchStaffOption({required this.id, required this.fullName, required this.role});

  final String id;
  final String fullName;
  final StaffRole role;
}

class _ShiftStaffMultiSelectState extends ConsumerState<ShiftStaffMultiSelect> {
  List<_BranchStaffOption> _options = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final branchId = ref.read(authSessionProvider).context?.activeBranchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Select an active branch before assigning staff.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await ref
          .read(supabaseClientProvider)
          .from('staff_branch_assignments')
          .select('staff_member_id, staff_members(id, full_name, role, is_active)')
          .eq('branch_id', branchId)
          .eq('is_deleted', false);

      final options = <_BranchStaffOption>[];
      for (final row in rows) {
        final staffRaw = row['staff_members'];
        if (staffRaw is! Map) {
          continue;
        }
        final staff = Map<String, dynamic>.from(staffRaw);
        if (staff['is_active'] != true) {
          continue;
        }
        final id = staff['id']?.toString();
        final fullName = staff['full_name']?.toString().trim();
        final role = StaffRole.tryParse(staff['role']?.toString());
        if (id == null || id.isEmpty || fullName == null || fullName.isEmpty || role == null) {
          continue;
        }
        options.add(_BranchStaffOption(id: id, fullName: fullName, role: role));
      }

      options.sort((a, b) => a.fullName.compareTo(b.fullName));

      if (!mounted) {
        return;
      }
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Could not load staff for this branch.';
      });
    }
  }

  void _toggleStaff(String staffId, bool selected) {
    final next = Set<String>.from(widget.selectedStaffIds);
    if (selected) {
      next.add(staffId);
    } else {
      next.remove(staffId);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'Staff (optional)'),
        child: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Loading staff…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: _loadStaff, child: const Text('Retry')),
        ],
      );
    }

    if (_options.isEmpty) {
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
        for (final option in _options)
          CheckboxListTile(
            key: Key('shift_staff_option_${option.id}'),
            value: widget.selectedStaffIds.contains(option.id),
            enabled: widget.enabled,
            title: Text(option.fullName),
            subtitle: Text(option.role.wireValue.replaceAll('_', ' ')),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: widget.enabled ? (checked) => _toggleStaff(option.id, checked ?? false) : null,
          ),
      ],
    );
  }
}
