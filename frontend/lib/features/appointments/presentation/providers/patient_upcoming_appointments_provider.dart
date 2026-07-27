import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/usecases/appointment_use_case_providers.dart';

/// Branch + patient pair for loading upcoming appointments on the detail page.
@immutable
class PatientDetailHistoryQuery {
  const PatientDetailHistoryQuery({required this.patientId, required this.branchId});

  final String patientId;
  final String branchId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PatientDetailHistoryQuery &&
            runtimeType == other.runtimeType &&
            patientId == other.patientId &&
            branchId == other.branchId;
  }

  @override
  int get hashCode => Object.hash(patientId, branchId);
}

/// Upcoming appointments for a patient (`list_appointments` with `p_patient_id`).
final patientUpcomingAppointmentsProvider = FutureProvider.autoDispose
    .family<List<AppointmentListItem>, PatientDetailHistoryQuery>((ref, query) {
      return ref.read(listPatientUpcomingAppointmentsUseCaseProvider).call(
        patientId: query.patientId,
        branchId: query.branchId,
      );
    });
