import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_select_items.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';

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
    return AppFormField(
      id: 'appointment_doctor',
      label: 'Doctor (optional)',
      child: AppSelect(
        key: key,
        options: AppointmentDoctorSelectItems.buildOptions(
          branchId: branchId,
          doctors: doctors,
          emptyLabel: 'No doctor assigned',
        ),
        value: value ?? '',
        disabled: !enabled,
        placeholder: 'No doctor assigned',
        onChanged: (doctorId) => onChanged(doctorId.isEmpty ? null : doctorId),
      ),
    );
  }
}
