import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';

/// Dropdown of active doctors for appointment booking (V1-4 US1).
class DoctorSelector extends ConsumerStatefulWidget {
  const DoctorSelector({required this.selectedDoctorId, required this.onChanged, this.enabled = true, super.key});

  final String? selectedDoctorId;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  ConsumerState<DoctorSelector> createState() => _DoctorSelectorState();
}

class _DoctorSelectorState extends ConsumerState<DoctorSelector> {
  List<StaffListItem> _doctors = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.active);
      if (!mounted) {
        return;
      }
      final doctors = staff.where((s) => s.role == StaffRole.doctor && s.isActive).toList(growable: false)
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
      setState(() {
        _doctors = doctors;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Could not load doctors.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'Doctor (optional)'),
        child: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Loading doctors…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: _loadDoctors, child: const Text('Retry')),
        ],
      );
    }

    if (_doctors.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'Doctor (optional)'),
        child: Text('No active doctors are configured. You can still book without assigning one.'),
      );
    }

    return DropdownButtonFormField<String?>(
      key: const Key('doctor_selector'),
      initialValue: widget.selectedDoctorId,
      decoration: const InputDecoration(labelText: 'Doctor (optional)'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('No doctor assigned')),
        for (final doctor in _doctors) DropdownMenuItem<String?>(value: doctor.id, child: Text(doctor.fullName)),
      ],
      onChanged: widget.enabled ? widget.onChanged : null,
    );
  }
}
