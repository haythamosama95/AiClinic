import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_select_items.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Doctor picker for appointment booking with branch-availability highlighting.
class AppointmentDoctorSelector extends StatelessWidget {
  const AppointmentDoctorSelector({
    required this.branchId,
    required this.doctors,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String branchId;
  final List<StaffListItem> doctors;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppSelect<String>(
      key: key,
      label: 'Doctor (optional)',
      richChildren: AppointmentDoctorSelectItems.build(
        context: context,
        branchId: branchId,
        doctors: doctors,
        emptyLabel: 'No doctor assigned',
      ),
      format: _formatValue,
      value: value ?? '',
      enabled: enabled,
      showPopoverCloseButton: true,
      onChanged: (doctorId) => onChanged(doctorId == null || doctorId.isEmpty ? null : doctorId),
    );
  }

  String _formatValue(String doctorId) {
    if (doctorId.isEmpty) {
      return 'No doctor assigned';
    }
    final doctor = doctors.where((entry) => entry.id == doctorId).firstOrNull;
    return doctor?.fullName ?? 'No doctor assigned';
  }
}
