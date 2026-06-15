import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/repositories/bootstrap_repository.dart';
import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_schedule.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';

typedef DevClinicSeedProgress = void Function(String message);

class _BranchSeedContext {
  const _BranchSeedContext({
    required this.branchId,
    required this.branchCode,
    required this.primaryDoctorId,
    this.secondaryDoctorId,
    required this.patientIds,
  });

  final String branchId;
  final String branchCode;
  final String primaryDoctorId;
  final String? secondaryDoctorId;
  final List<String> patientIds;
}

/// Resets the installation and seeds a multi-branch demo clinic (debug builds only).
class DevClinicSeedService {
  DevClinicSeedService({
    required BootstrapRepository bootstrap,
    required BranchRepository branches,
    required ProvisioningRepository provisioning,
    required StaffAdminRepository staffAdmin,
    required PatientRepository patients,
    required AppointmentRepository appointments,
    required VisitRepository visits,
  }) : _bootstrap = bootstrap,
       _branches = branches,
       _provisioning = provisioning,
       _staffAdmin = staffAdmin,
       _patients = patients,
       _appointments = appointments,
       _visits = visits;

  final BootstrapRepository _bootstrap;
  final BranchRepository _branches;
  final ProvisioningRepository _provisioning;
  final StaffAdminRepository _staffAdmin;
  final PatientRepository _patients;
  final AppointmentRepository _appointments;
  final VisitRepository _visits;

  Future<void> run({
    required AuthSessionContext auth,
    required Future<void> Function() refreshSession,
    DevClinicSeedProgress? onProgress,
  }) async {
    if (!auth.staffProfile.isBootstrapAdmin) {
      throw StateError('Only the bootstrap administrator can fill dummy clinic data.');
    }

    void report(String message) {
      AppLog.info('dev_clinic_seed.$message');
      onProgress?.call(message);
    }

    report('Wiping all clinic data from the server…');
    await _bootstrap.resetInstallationForDevelopment();
    await refreshSession();

    final doctorIdsByBranch = <String, String>{};
    String? multiBranchDoctorId;

    final firstBranch = DevClinicSeedSpec.branches.first;
    report('Creating organization and first branch…');
    final bootstrapResult = await _bootstrap.finishSetup(
      BootstrapFinishSetupInput(
        organization: const BootstrapOrganizationInput(
          name: DevClinicSeedSpec.organizationName,
          currencyCode: DevClinicSeedSpec.currencyCode,
          timezone: DevClinicSeedSpec.timezone,
        ),
        branch: BootstrapBranchInput(
          organizationId: '',
          name: firstBranch.name,
          code: firstBranch.code,
          address: firstBranch.address,
          phone: firstBranch.phone,
          mapsUrl: firstBranch.mapsUrl,
          workingSchedule: DevClinicSeedSpec.workingScheduleFor(firstBranch.scheduleKind),
        ),
        staffAccounts: [
          for (final staff in firstBranch.branchStaff)
            CreateStaffAccountInput(
              username: staff.username,
              password: DevClinicSeedSpec.defaultStaffPassword,
              fullName: staff.fullName,
              role: _staffRole(staff.role),
              branchIds: const [],
            ),
        ],
      ),
    );
    await refreshSession();

    final branchIds = <String>[bootstrapResult.branchId];
    for (var staffIndex = 0; staffIndex < firstBranch.branchStaff.length; staffIndex++) {
      final staff = firstBranch.branchStaff[staffIndex];
      if (staff.role == DevClinicStaffRole.doctor && staffIndex < bootstrapResult.staffMemberIds.length) {
        doctorIdsByBranch[bootstrapResult.branchId] = bootstrapResult.staffMemberIds[staffIndex];
      }
    }

    for (var index = 1; index < DevClinicSeedSpec.branches.length; index++) {
      final spec = DevClinicSeedSpec.branches[index];
      report('Creating branch ${spec.name}…');
      final branchId = await _branches.createBranch(
        CreateBranchInput(
          name: spec.name,
          code: spec.code,
          address: spec.address,
          phone: spec.phone,
          mapsUrl: spec.mapsUrl,
          workingSchedule: DevClinicSeedSpec.workingScheduleFor(spec.scheduleKind),
        ),
      );
      branchIds.add(branchId);
    }

    report('Assigning branches to your account…');
    await _assignBootstrapAdminToBranches(auth.staffProfile.staffMemberId, branchIds);
    await refreshSession();

    for (var branchIndex = 1; branchIndex < DevClinicSeedSpec.branches.length; branchIndex++) {
      final spec = DevClinicSeedSpec.branches[branchIndex];
      final branchId = branchIds[branchIndex];
      for (final staff in spec.branchStaff) {
        report('Creating staff ${staff.fullName}…');
        final created = await _provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: staff.username,
            password: DevClinicSeedSpec.defaultStaffPassword,
            fullName: staff.fullName,
            role: _staffRole(staff.role),
            branchIds: [branchId],
            primaryBranchId: branchId,
          ),
        );
        if (staff.role == DevClinicStaffRole.doctor) {
          doctorIdsByBranch[branchId] = created.staffMemberId;
        }
      }
    }

    for (final staff in DevClinicSeedSpec.allBranchStaff) {
      report('Creating staff ${staff.fullName}…');
      final created = await _provisioning.createStaffAccount(
        CreateStaffAccountInput(
          username: staff.username,
          password: DevClinicSeedSpec.defaultStaffPassword,
          fullName: staff.fullName,
          role: _staffRole(staff.role),
          branchIds: List<String>.from(branchIds),
          primaryBranchId: branchIds.first,
        ),
      );
      if (staff.role == DevClinicStaffRole.doctor) {
        multiBranchDoctorId = created.staffMemberId;
      }
    }

    await refreshSession();

    final branchContexts = <_BranchSeedContext>[];
    var patientCount = 0;
    final totalPatients = DevClinicSeedSpec.patientsPerBranch * branchIds.length;
    for (var branchIndex = 0; branchIndex < branchIds.length; branchIndex++) {
      final branchId = branchIds[branchIndex];
      final branchCode = DevClinicSeedSpec.branches[branchIndex].code;
      final primaryDoctorId = doctorIdsByBranch[branchId];
      if (primaryDoctorId == null || primaryDoctorId.isEmpty) {
        throw StateError('No doctor was created for branch $branchCode.');
      }

      final patientIds = <String>[];
      for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
        patientCount++;
        if (patientCount == 1 || patientCount % 10 == 0 || patientCount == totalPatients) {
          report('Creating patients ($patientCount/$totalPatients)…');
        }

        final patientId = await _createPatient(
          branchId: branchId,
          branchIndex: branchIndex + 1,
          branchCode: branchCode,
          patientIndex: patientIndex,
        );
        patientIds.add(patientId);
      }

      branchContexts.add(
        _BranchSeedContext(
          branchId: branchId,
          branchCode: branchCode,
          primaryDoctorId: primaryDoctorId,
          secondaryDoctorId: multiBranchDoctorId,
          patientIds: patientIds,
        ),
      );
    }

    await _seedAppointmentsAndVisits(branchContexts: branchContexts, onProgress: report);

    report('Refreshing session…');
    await refreshSession();
    report('Done');
  }

  Future<void> _seedAppointmentsAndVisits({
    required List<_BranchSeedContext> branchContexts,
    required DevClinicSeedProgress onProgress,
  }) async {
    final referenceUtc = DateTime.now().toUtc();
    var appointmentCount = 0;
    final totalAppointments =
        branchContexts.length *
        DevClinicSeedSpec.patientsPerBranch *
        DevClinicSeedSchedule.appointmentDayOffsets.length;

    for (final branch in branchContexts) {
      for (var patientIndex = 1; patientIndex <= branch.patientIds.length; patientIndex++) {
        final patientId = branch.patientIds[patientIndex - 1];
        final doctorId = _doctorForPatient(
          primaryDoctorId: branch.primaryDoctorId,
          secondaryDoctorId: branch.secondaryDoctorId,
          patientIndex: patientIndex,
        );

        for (final dayOffset in DevClinicSeedSchedule.appointmentDayOffsets) {
          appointmentCount++;
          if (appointmentCount == 1 || appointmentCount % 25 == 0 || appointmentCount == totalAppointments) {
            onProgress('Creating appointments ($appointmentCount/$totalAppointments)…');
          }

          final seedKey = patientIndex + dayOffset;
          final targetStatus = DevClinicSeedSchedule.appointmentStatusFor(dayOffset: dayOffset, seedKey: seedKey);
          final startTime = DevClinicSeedSchedule.appointmentStartUtc(
            timezone: DevClinicSeedSpec.timezone,
            dayOffset: dayOffset,
            patientIndex: patientIndex,
            referenceUtc: referenceUtc,
          );

          final created = await _appointments.createAppointment(
            branchId: branch.branchId,
            patientId: patientId,
            doctorId: doctorId,
            type: AppointmentType.planned,
            startTime: startTime,
            durationMinutes: DevClinicSeedSchedule.appointmentDurationMinutesFor(seedKey),
            notes: DevClinicSeedSchedule.appointmentNotes(
              branchCode: branch.branchCode,
              patientIndex: patientIndex,
              dayOffset: dayOffset,
              status: targetStatus,
            ),
          );

          await _applyAppointmentTarget(
            appointmentId: created.appointmentId,
            targetStatus: targetStatus,
            branchCode: branch.branchCode,
            patientIndex: patientIndex,
            dayOffset: dayOffset,
            seedKey: seedKey,
          );
        }
      }
    }
  }

  Future<void> _applyAppointmentTarget({
    required String appointmentId,
    required AppointmentStatus targetStatus,
    required String branchCode,
    required int patientIndex,
    required int dayOffset,
    required int seedKey,
  }) async {
    if (targetStatus == AppointmentStatus.cancelled) {
      await _appointments.cancelAppointment(
        appointmentId: appointmentId,
        reason: 'Dev seed cancellation for $branchCode patient #$patientIndex.',
      );
      return;
    }

    for (final status in DevClinicSeedSchedule.advancementPathTo(targetStatus)) {
      await _appointments.updateAppointmentStatus(appointmentId: appointmentId, newStatus: status);
    }

    final documentation = DevClinicSeedSchedule.visitDocumentationFor(status: targetStatus, seedKey: seedKey);
    if (!DevClinicSeedSchedule.shouldSeedVisit(targetStatus) || documentation == DevClinicVisitDocumentationKind.none) {
      return;
    }

    final visit = await _visits.createVisit(appointmentId: appointmentId);

    final soap = DevClinicSeedSchedule.soapContentFor(
      kind: documentation,
      branchCode: branchCode,
      patientIndex: patientIndex,
      dayOffset: dayOffset,
    );

    final detail = await _visits.getVisit(visitId: visit.visitId);
    final soapUpdatedAt = detail.soap?.updatedAt;
    if (soapUpdatedAt == null) {
      throw StateError('Visit SOAP row missing after create for dev seed.');
    }

    final saved = await _visits.saveSoapNote(
      visitId: visit.visitId,
      expectedUpdatedAt: soapUpdatedAt,
      subjective: soap.subjective,
      objective: soap.objective,
      assessment: soap.assessment,
      plan: soap.plan,
      specialtyFormJson: soap.specialtyFormJson.isEmpty ? null : soap.specialtyFormJson,
    );

    if (DevClinicSeedSchedule.shouldCompleteVisit(targetStatus)) {
      final treatment = DevClinicSeedSchedule.treatmentPlanFor(branchCode: branchCode, patientIndex: patientIndex);
      await _visits.createTreatmentPlan(
        visitId: visit.visitId,
        medicationName: treatment.medicationName,
        dosage: treatment.dosage,
        frequency: treatment.frequency,
        duration: treatment.duration,
        notes: treatment.notes,
      );
      await _visits.completeVisit(visitId: visit.visitId, expectedUpdatedAt: saved.updatedAt);
    }
  }

  Future<void> _assignBootstrapAdminToBranches(String staffMemberId, List<String> branchIds) async {
    final detail = await _staffAdmin.fetchStaffMember(staffMemberId);
    if (detail == null) {
      throw StateError('Could not load the bootstrap administrator profile.');
    }

    await _staffAdmin.updateStaffMember(
      UpdateStaffMemberInput(
        staffMemberId: staffMemberId,
        fullName: detail.fullName,
        role: detail.role,
        branchIds: branchIds,
        phone: detail.phone,
        primaryBranchId: branchIds.first,
      ),
    );
  }

  Future<String> _createPatient({
    required String branchId,
    required int branchIndex,
    required String branchCode,
    required int patientIndex,
  }) async {
    final seedKey = branchIndex * 1000 + patientIndex;
    final input = CreatePatientInput(
      activeBranchId: branchId,
      fullName: DevClinicSeedSpec.patientFullName(branchCode: branchCode, index: patientIndex),
      phone: DevClinicSeedSpec.patientPhone(branchIndex: branchIndex, patientIndex: patientIndex),
      dateOfBirth: DevClinicSeedSchedule.patientDateOfBirth(seedKey),
      gender: DevClinicSeedSchedule.patientGender(seedKey),
      maritalStatus: DevClinicSeedSchedule.patientMaritalStatus(seedKey),
      notes: DevClinicSeedSchedule.patientNotes(branchCode: branchCode, patientIndex: patientIndex),
    );

    try {
      return await _patients.createPatient(input);
    } on RpcFailure catch (error) {
      if (!error.isDuplicateWarning) {
        rethrow;
      }
      return _patients.createPatient(
        CreatePatientInput(
          activeBranchId: branchId,
          fullName: input.fullName,
          phone: input.phone,
          dateOfBirth: input.dateOfBirth,
          gender: input.gender,
          maritalStatus: input.maritalStatus,
          notes: input.notes,
          acknowledgeDuplicate: true,
        ),
      );
    }
  }

  static String _doctorForPatient({
    required String primaryDoctorId,
    required String? secondaryDoctorId,
    required int patientIndex,
  }) {
    if (secondaryDoctorId == null || patientIndex.isEven) {
      return primaryDoctorId;
    }
    return secondaryDoctorId;
  }

  static StaffRole _staffRole(DevClinicStaffRole role) {
    return switch (role) {
      DevClinicStaffRole.doctor => StaffRole.doctor,
      DevClinicStaffRole.receptionist => StaffRole.receptionist,
    };
  }
}
