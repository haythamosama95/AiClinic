import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';

/// Local patient view model for the appointment booking flow.
@immutable
class AppointmentBookingPatient {
  const AppointmentBookingPatient({required this.id, required this.fullName, this.branchLabel});

  final String id;
  final String fullName;
  final String? branchLabel;

  factory AppointmentBookingPatient.fromPatientListItem(PatientListItem item) {
    return AppointmentBookingPatient(
      id: item.id,
      fullName: item.fullName,
      branchLabel: item.registeringBranchName,
    );
  }

  factory AppointmentBookingPatient.fromAppointmentDetail(AppointmentDetail detail, {String? branchLabel}) {
    return AppointmentBookingPatient(
      id: detail.patientId,
      fullName: detail.patientName,
      branchLabel: branchLabel?.trim().isNotEmpty == true ? branchLabel!.trim() : null,
    );
  }

  PatientListItem toPatientListItem({required String registeringBranchId}) {
    return PatientListItem(
      id: id,
      fullName: fullName,
      registeringBranchId: registeringBranchId,
      registeringBranchName: branchLabel?.trim().isNotEmpty == true ? branchLabel!.trim() : '—',
    );
  }
}
