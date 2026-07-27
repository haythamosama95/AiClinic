import 'package:clock/clock.dart';

import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

class ListPatientUpcomingAppointments {
  const ListPatientUpcomingAppointments(this._repository);

  final AppointmentRepository _repository;

  Future<List<AppointmentListItem>> call({
    required String patientId,
    required String branchId,
  }) async {
    final now = clock.now().toUtc();
    final items = await _repository.listAppointments(
      branchId: branchId,
      from: now,
      to: now.add(const Duration(days: 365)),
      patientId: patientId,
      statuses: const [
        AppointmentStatus.scheduled,
        AppointmentStatus.confirmed,
        AppointmentStatus.checkedIn,
        AppointmentStatus.inProgress,
      ],
    );

    return [...items]..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}
