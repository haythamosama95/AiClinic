import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Branch + patient pair for loading upcoming appointments on the detail page.
@immutable
class PatientUpcomingAppointmentsQuery {
  const PatientUpcomingAppointmentsQuery({required this.patientId, required this.branchId});

  final String patientId;
  final String branchId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PatientUpcomingAppointmentsQuery &&
            runtimeType == other.runtimeType &&
            patientId == other.patientId &&
            branchId == other.branchId;
  }

  @override
  int get hashCode => Object.hash(patientId, branchId);
}

/// Upcoming appointments for a patient (`list_appointments` with `p_patient_id`).
final patientUpcomingAppointmentsForPatientProvider = FutureProvider.autoDispose
    .family<List<AppointmentListItem>, PatientUpcomingAppointmentsQuery>((ref, query) async {
      final now = clock.now().toUtc();
      final items = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(
            branchId: query.branchId,
            from: now,
            to: now.add(const Duration(days: 365)),
            patientId: query.patientId,
            statuses: const [
              AppointmentStatus.scheduled,
              AppointmentStatus.confirmed,
              AppointmentStatus.checkedIn,
              AppointmentStatus.inProgress,
            ],
          );

      return [...items]..sort((a, b) => a.startTime.compareTo(b.startTime));
    });
