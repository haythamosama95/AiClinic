import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/patient_dev_seed_data.dart';
import 'package:ai_clinic/features/patients/domain/patient_dev_seed_spec.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';

/// Outcome of a dev patient seed run.
class PatientDevSeedOutcome {
  const PatientDevSeedOutcome({
    required this.created,
    required this.archived,
    required this.skippedBecauseAlreadySeeded,
    this.otherBranchName,
    this.errorMessage,
  });

  final int created;
  final int archived;
  final bool skippedBecauseAlreadySeeded;
  final String? otherBranchName;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

/// Creates demo patients for local testing (debug builds only).
class PatientDevSeedService {
  PatientDevSeedService({
    required PatientRepository patients,
    required BranchRepository branches,
    required StaffAdminRepository staffAdmin,
  }) : _patients = patients,
       _branches = branches,
       _staffAdmin = staffAdmin;

  final PatientRepository _patients;
  final BranchRepository _branches;
  final StaffAdminRepository _staffAdmin;

  static const _secondBranchName = 'Dev Second Branch';
  static const _secondBranchCode = 'DEV-2ND';

  Future<PatientDevSeedOutcome> seed(
    AuthSessionContext auth, {
    required Future<void> Function() reloadAuthContext,
  }) async {
    final organizationId = auth.organizationId;
    final mainBranchId = auth.activeBranchId ?? auth.branchIds.firstOrNull;
    if (organizationId == null || organizationId.isEmpty || mainBranchId == null) {
      return const PatientDevSeedOutcome(
        created: 0,
        archived: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: 'Select an active branch before seeding patients.',
      );
    }

    final existing = await _patients.searchPatients(
      query: PatientDevSeedSpec.devNamePrefix.trim(),
      scope: PatientListScope.allBranches,
      limit: 1,
    );
    if (existing.totalCount > 0) {
      AppLog.info('patients.dev_seed.skip_already_present count=${existing.totalCount}');
      return PatientDevSeedOutcome(created: 0, archived: 0, skippedBecauseAlreadySeeded: true, otherBranchName: null);
    }

    AppLog.info('patients.dev_seed.start main_branch=$mainBranchId');

    try {
      final orgBranches = await _branches.listBranches(organizationId: organizationId, filter: BranchListFilter.active);
      var otherBranchId = _pickOtherBranchId(orgBranches, mainBranchId);

      if (otherBranchId == null) {
        otherBranchId = await _branches.createBranch(
          const CreateBranchInput(name: _secondBranchName, code: _secondBranchCode, address: 'Dev seed address'),
        );
        AppLog.info('patients.dev_seed.second_branch_created id=$otherBranchId');
      }

      final assignmentChanged = await _ensureStaffAssignedToBranch(auth, otherBranchId);
      if (assignmentChanged) {
        await reloadAuthContext();
      }

      var created = 0;
      var archived = 0;
      String? otherBranchLabel;

      for (final orgBranch in orgBranches) {
        if (orgBranch.id == otherBranchId) {
          otherBranchLabel = orgBranch.name;
        }
      }
      otherBranchLabel ??= _secondBranchName;

      for (final spec in PatientDevSeedData.patients) {
        final branchId = spec.branchTarget == PatientDevSeedBranchTarget.other ? otherBranchId : mainBranchId;

        final patientId = await _createWithDuplicateAck(spec, branchId);
        created++;

        if (spec.archiveAfterCreate) {
          await _patients.archivePatient(patientId);
          archived++;
        }
      }

      AppLog.info('patients.dev_seed.done created=$created archived=$archived');
      return PatientDevSeedOutcome(
        created: created,
        archived: archived,
        skippedBecauseAlreadySeeded: false,
        otherBranchName: otherBranchLabel,
      );
    } on RpcFailure catch (error) {
      AppLog.warning('patients.dev_seed.rpc_failed code=${error.code}');
      return PatientDevSeedOutcome(
        created: 0,
        archived: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: error.result.errorMessage ?? 'Patient seed failed (${error.code}).',
      );
    } catch (error, stack) {
      AppLog.warning('patients.dev_seed.failed reason=${error.runtimeType}');
      AppLog.fine('patients.dev_seed.stack $stack');
      return PatientDevSeedOutcome(
        created: 0,
        archived: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: 'Patient seed failed: $error',
      );
    }
  }

  Future<String> _createWithDuplicateAck(PatientDevSeedSpec spec, String branchId) async {
    final input = CreatePatientInput(
      activeBranchId: branchId,
      fullName: spec.fullName,
      phone: spec.phone,
      dateOfBirth: spec.dateOfBirth,
      gender: spec.gender,
      maritalStatus: spec.maritalStatus,
      notes: spec.notes,
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
          fullName: spec.fullName,
          phone: spec.phone,
          dateOfBirth: spec.dateOfBirth,
          gender: spec.gender,
          maritalStatus: spec.maritalStatus,
          notes: spec.notes,
          acknowledgeDuplicate: true,
        ),
      );
    }
  }

  Future<bool> _ensureStaffAssignedToBranch(AuthSessionContext auth, String branchId) async {
    if (auth.branchIds.contains(branchId)) {
      return false;
    }

    final staffId = auth.staffProfile.staffMemberId;
    final detail = await _staffAdmin.fetchStaffMember(staffId);
    if (detail == null) {
      throw StateError('Could not load your staff profile to assign the second branch.');
    }

    final branchIds = [...detail.branchIds];
    if (!branchIds.contains(branchId)) {
      branchIds.add(branchId);
    }

    await _staffAdmin.updateStaffMember(
      UpdateStaffMemberInput(
        staffMemberId: staffId,
        fullName: detail.fullName,
        role: detail.role,
        branchIds: branchIds,
        phone: detail.phone,
        primaryBranchId: detail.primaryBranchId ?? auth.activeBranchId,
      ),
    );
    AppLog.info('patients.dev_seed.staff_assigned_second_branch branch_id=$branchId');
    return true;
  }

  static String? _pickOtherBranchId(List<BranchListItem> orgBranches, String mainBranchId) {
    for (final branch in orgBranches) {
      if (branch.id != mainBranchId) {
        return branch.id;
      }
    }
    return null;
  }
}
