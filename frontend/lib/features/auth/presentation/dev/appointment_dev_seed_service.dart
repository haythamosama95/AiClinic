import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';

const int appointmentDevSeedPlannedCount = 6;
const int appointmentDevSeedWalkInCount = 4;

class AppointmentDevSeedOutcome {
  const AppointmentDevSeedOutcome({required this.isSuccess, this.errorMessage});

  final bool isSuccess;
  final String? errorMessage;
}

/// Creates mixed planned and walk-in demo appointments at the active branch.
class AppointmentDevSeedService {
  AppointmentDevSeedService({
    required AppointmentRepository appointments,
    required SearchPatients searchPatients,
    required ListStaff listStaff,
  }) : _appointments = appointments,
       _searchPatients = searchPatients,
       _listStaff = listStaff;

  final AppointmentRepository _appointments;
  final SearchPatients _searchPatients;
  final ListStaff _listStaff;

  Future<AppointmentDevSeedOutcome> seed({required String branchId}) async {
    try {
      final patientsPage = await _searchPatients(scope: PatientListScope.thisBranch, branchId: branchId, limit: 20);
      final patients = patientsPage.items;
      if (patients.isEmpty) {
        return const AppointmentDevSeedOutcome(
          isSuccess: false,
          errorMessage: 'No patients found in the active branch. Seed patients first.',
        );
      }

      final staff = await _listStaff(filter: StaffListFilter.active);
      final doctorIds = staff
          .where((item) => item.role.name == 'doctor' && item.isActive)
          .map((item) => item.id)
          .toList(growable: false);

      final now = DateTime.now();
      final rounded = DateTime(now.year, now.month, now.day, now.hour, ((now.minute + 14) ~/ 15) * 15);
      final plannedStart = rounded.add(const Duration(minutes: 30));

      for (var i = 0; i < appointmentDevSeedPlannedCount; i++) {
        final patient = patients[i % patients.length];
        final doctorId = doctorIds.isEmpty ? null : doctorIds[i % doctorIds.length];
        await _appointments.createAppointment(
          branchId: branchId,
          patientId: patient.id,
          doctorId: doctorId,
          type: AppointmentType.planned,
          startTime: plannedStart.add(Duration(minutes: i * 30)),
          durationMinutes: 30,
          notes: '[Dev] Planned seed #${i + 1}',
        );
      }

      for (var i = 0; i < appointmentDevSeedWalkInCount; i++) {
        final patient = patients[(appointmentDevSeedPlannedCount + i) % patients.length];
        final doctorId = doctorIds.isEmpty ? null : doctorIds[(appointmentDevSeedPlannedCount + i) % doctorIds.length];
        await _appointments.createAppointment(
          branchId: branchId,
          patientId: patient.id,
          doctorId: doctorId,
          type: AppointmentType.walkIn,
          durationMinutes: 20,
          notes: '[Dev] Walk-in seed #${i + 1}',
        );
      }

      return const AppointmentDevSeedOutcome(isSuccess: true);
    } on RpcFailure catch (error) {
      return AppointmentDevSeedOutcome(
        isSuccess: false,
        errorMessage: error.result.errorMessage ?? 'Failed to seed appointments (${error.code}).',
      );
    } catch (error, stack) {
      AppLog.warning('appointments.dev_seed.failed reason=${error.runtimeType}');
      AppLog.fine('appointments.dev_seed.stack $stack');
      return AppointmentDevSeedOutcome(isSuccess: false, errorMessage: 'Failed to seed appointments: $error');
    }
  }
}
