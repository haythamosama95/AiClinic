import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/dev/appointment_dev_seed_schedule.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/usecases/search_patients.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';

const int appointmentDevSeedPlannedCount = 6;
const int appointmentDevSeedWalkInCount = 4;

class AppointmentDevSeedOutcome {
  const AppointmentDevSeedOutcome({
    required this.isSuccess,
    this.errorMessage,
    this.plannedCreated = 0,
    this.walkInCreated = 0,
  });

  final bool isSuccess;
  final String? errorMessage;
  final int plannedCreated;
  final int walkInCreated;
}

/// Creates mixed planned and walk-in demo appointments at the active branch.
class AppointmentDevSeedService {
  AppointmentDevSeedService({
    required AppointmentRepository appointments,
    required SearchPatients searchPatients,
    required ListStaff listStaff,
    required BranchRepository branches,
  }) : _appointments = appointments,
       _searchPatients = searchPatients,
       _listStaff = listStaff,
       _branches = branches;

  final AppointmentRepository _appointments;
  final SearchPatients _searchPatients;
  final ListStaff _listStaff;
  final BranchRepository _branches;

  Future<AppointmentDevSeedOutcome> seed({
    required String branchId,
    required String organizationId,
    DateTime? referenceNow,
  }) async {
    try {
      final schedule = await _resolveWorkingSchedule(organizationId: organizationId, branchId: branchId);

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
          .where((item) => item.role == StaffRole.doctor && item.isActive)
          .map((item) => item.id)
          .toList(growable: false);

      final plannedStarts = AppointmentDevSeedSchedule.plannedStartTimes(
        schedule: schedule,
        count: appointmentDevSeedPlannedCount,
        reference: referenceNow,
      );
      if (plannedStarts.length < appointmentDevSeedPlannedCount) {
        return const AppointmentDevSeedOutcome(
          isSuccess: false,
          errorMessage: 'Could not find enough working-hour slots for planned appointments. Check branch hours.',
        );
      }

      for (var i = 0; i < appointmentDevSeedPlannedCount; i++) {
        final patient = patients[i % patients.length];
        final doctorId = doctorIds.isEmpty ? null : doctorIds[i % doctorIds.length];
        await _appointments.createAppointment(
          branchId: branchId,
          patientId: patient.id,
          doctorId: doctorId,
          type: AppointmentType.planned,
          startTime: plannedStarts[i],
          durationMinutes: 30,
          notes: '[Dev] Planned seed #${i + 1}',
        );
      }

      var walkInCreated = 0;
      if (doctorIds.isEmpty) {
        AppLog.info('appointments.dev_seed.walk_ins_skipped reason=no_doctors');
        return AppointmentDevSeedOutcome(isSuccess: true, plannedCreated: appointmentDevSeedPlannedCount);
      }

      if (!AppointmentDevSeedSchedule.canAssignWalkInToday(schedule: schedule, reference: referenceNow)) {
        AppLog.info('appointments.dev_seed.walk_ins_skipped reason=outside_working_hours');
        return AppointmentDevSeedOutcome(isSuccess: true, plannedCreated: appointmentDevSeedPlannedCount);
      }

      for (var i = 0; i < appointmentDevSeedWalkInCount; i++) {
        final patient = patients[(appointmentDevSeedPlannedCount + i) % patients.length];
        final doctorId = doctorIds[(appointmentDevSeedPlannedCount + i) % doctorIds.length];
        await _appointments.createAppointment(
          branchId: branchId,
          patientId: patient.id,
          doctorId: doctorId,
          type: AppointmentType.walkIn,
          durationMinutes: 20,
          notes: '[Dev] Walk-in seed #${i + 1}',
        );
        walkInCreated++;
      }

      return AppointmentDevSeedOutcome(
        isSuccess: true,
        plannedCreated: appointmentDevSeedPlannedCount,
        walkInCreated: walkInCreated,
      );
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

  Future<BranchWorkingSchedule> _resolveWorkingSchedule({
    required String organizationId,
    required String branchId,
  }) async {
    final branches = await _branches.listBranches(organizationId: organizationId, filter: BranchListFilter.active);
    for (final branch in branches) {
      if (branch.id == branchId) {
        return branch.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();
      }
    }
    return BranchWorkingSchedule.defaultSchedule();
  }
}
