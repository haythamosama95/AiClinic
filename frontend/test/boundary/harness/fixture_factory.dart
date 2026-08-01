import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/setup/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/setup/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';

import 'boundary_session.dart';
import 'reset.dart';
import 'sql_fixture_helper.dart';

/// Deterministic clinic fixture created via the same RPCs the app uses.
class BoundaryClinicFixture {
  BoundaryClinicFixture({
    required this.seq,
    required this.suffix,
    required this.organizationId,
    required this.branchId,
    required this.organizationName,
    required this.branchCode,
  });

  /// Monotonic id so generated staff usernames stay unique across resets.
  final int seq;
  final String suffix;
  final String organizationId;
  final String branchId;
  final String organizationName;
  final String branchCode;

  String phone([String tail = '01']) {
    final digits = '${suffix.hashCode.abs()}'.padLeft(10, '0').substring(0, 10);
    return '+1$digits$tail';
  }

  /// Staff usernames must be 3–32 chars ([staff_username.dart]); keep tag short.
  ///
  /// Uses [suffix] (per-test label) so usernames stay unique across installation
  /// resets even when [_clinicSeq] is cleared.
  String usernameFor(StaffRole role) {
    final prefix = 'bd_${role.wireValue}_';
    final maxTag = 32 - prefix.length;
    final tag = suffix;
    return '$prefix${tag.length <= maxTag ? tag : tag.substring(0, maxTag)}';
  }
}

bool _isRetryableStaffProvisionError(String? code) =>
    code == 'ORG_SETUP_INCOMPLETE' || code == 'INVALID_BRANCH';

class FixtureFactory {
  FixtureFactory(this.client);

  final SupabaseClient client;

  static int _counter = 0;
  static int _clinicSeq = 0;

  /// Clears monotonic fixture ids after [devResetAsBootstrapAdmin].
  static void resetStaticState() {
    _counter = 0;
    _clinicSeq = 0;
  }

  /// Bootstraps a fresh org + branch (caller must reset installation first).
  Future<BoundaryClinicFixture> bootstrapOnly({String? label}) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        return await _bootstrapOnlyAttempt(label: label);
      } on RpcFailure catch (error) {
        if (error.code == 'ORG_ALREADY_EXISTS' && attempt < 4) {
          await SqlFixtureHelper().forcePurgeInstallation();
          await devResetAsBootstrapAdmin(client);
          await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }

    throw StateError('bootstrapOnly failed after retry');
  }

  Future<BoundaryClinicFixture> _bootstrapOnlyAttempt({String? label}) async {
    final seq = ++_clinicSeq;
    final suffix = label ?? '${DateTime.now().millisecondsSinceEpoch}${_counter++}';
    final auth = AuthRepositoryImpl(client);
    final bootstrap = BootstrapRepositoryImpl(client);

    await auth.signIn(username: 'admin', password: 'admin');
    await auth.refreshSession();

    final orgName = 'Boundary Clinic $suffix';
    final orgId = await bootstrap.createOrganization(BootstrapOrganizationInput(name: orgName));
    final branchCode = 'BD${suffix.hashCode.abs() % 100000}';
    final branchId = await bootstrap.createBranch(
      BootstrapBranchInput(organizationId: orgId, name: 'Main $suffix', code: branchCode),
    );

    final clinic = BoundaryClinicFixture(
      seq: seq,
      suffix: suffix,
      organizationId: orgId,
      branchId: branchId,
      organizationName: orgName,
      branchCode: branchCode,
    );
    await SqlFixtureHelper().waitForActiveBranch(branchId: branchId, organizationId: orgId);
    await boundaryRefreshSessionForClinic(
      auth,
      clinic,
      username: 'admin',
      password: 'admin',
    );
    await auth.signOut();

    return clinic;
  }

  /// Resets installation and bootstraps a fresh org + branch.
  Future<BoundaryClinicFixture> resetAndBootstrap({String? label}) async {
    await devResetAsBootstrapAdmin(client);
    return bootstrapOnly(label: label);
  }

  Future<({String username, String password, String staffMemberId})> createStaff({
    required BoundaryClinicFixture clinic,
    required StaffRole role,
    String password = 'TestPass1',
  }) async {
    final auth = AuthRepositoryImpl(client);
    final provisioning = ProvisioningRepositoryImpl(client);

    await auth.signIn(username: 'admin', password: 'admin');
    await auth.refreshSession();

    final username = clinic.usernameFor(role);
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await SqlFixtureHelper().waitForActiveBranch(
          branchId: clinic.branchId,
          organizationId: clinic.organizationId,
        );
        await boundaryRefreshSessionForClinic(
          auth,
          clinic,
          username: 'admin',
          password: 'admin',
        );
        final result = await provisioning.createStaffAccount(
          CreateStaffAccountInput(
            username: username,
            password: password,
            fullName: 'Staff ${role.wireValue} ${clinic.suffix}',
            role: role,
            branchIds: [clinic.branchId],
            primaryBranchId: clinic.branchId,
          ),
        );

        await auth.signOut();
        return (username: username, password: password, staffMemberId: result.staffMemberId);
      } on RpcFailure catch (error) {
        if (_isRetryableStaffProvisionError(error.code) && attempt < 4) {
          await auth.signOut();
          await auth.signIn(username: 'admin', password: 'admin');
          await boundaryRefreshSessionForClinic(
            auth,
            clinic,
            username: 'admin',
            password: 'admin',
          );
          await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
          continue;
        }
        await auth.signOut();
        rethrow;
      }
    }

    await auth.signOut();
    throw StateError('createStaff failed after retry');
  }

  Future<String> createPatient({
    required BoundaryClinicFixture clinic,
    required StaffRole asRole,
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    bool acknowledgeDuplicate = false,
  }) async {
    final auth = AuthRepositoryImpl(client);
    if (asRole == StaffRole.administrator) {
      await auth.signIn(username: 'admin', password: 'admin');
      await boundaryRefreshSessionForClinic(
        auth,
        clinic,
        username: 'admin',
        password: 'admin',
      );
    } else {
      final creds = await createStaff(clinic: clinic, role: asRole);
      await auth.signIn(username: creds.username, password: creds.password);
      await boundaryRefreshSessionForClinic(
        auth,
        clinic,
        username: creds.username,
        password: creds.password,
      );
    }

    final repo = PatientRepositoryImpl(client);
    final result = await repo.createPatient(
      CreatePatientInput(
        activeBranchId: clinic.branchId,
        fullName: fullName ?? 'Patient ${clinic.suffix}',
        phone: phone ?? clinic.phone(),
        dateOfBirth: dateOfBirth,
        acknowledgeDuplicate: acknowledgeDuplicate,
      ),
    );

    await auth.signOut();
    return result.patientId;
  }

  Future<String> createPatientAsAdmin({
    required BoundaryClinicFixture clinic,
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    bool acknowledgeDuplicate = false,
  }) {
    return createPatient(
      clinic: clinic,
      asRole: StaffRole.administrator,
      fullName: fullName,
      phone: phone,
      dateOfBirth: dateOfBirth,
      acknowledgeDuplicate: acknowledgeDuplicate,
    );
  }

  Future<String> createPatientFullDemographics({required BoundaryClinicFixture clinic}) async {
    final creds = await createStaff(clinic: clinic, role: StaffRole.receptionist);
    final auth = AuthRepositoryImpl(client);
    await auth.signIn(username: creds.username, password: creds.password);
    await boundaryRefreshSessionForClinic(
      auth,
      clinic,
      username: creds.username,
      password: creds.password,
    );

    final repo = PatientRepositoryImpl(client);
    final result = await repo.createPatient(
      CreatePatientInput(
        activeBranchId: clinic.branchId,
        fullName: 'Full Demo ${clinic.suffix}',
        phone: clinic.phone('99'),
        dateOfBirth: DateTime(1990, 5, 15),
        gender: PatientGender.female,
        notes: 'boundary notes',
        acknowledgeDuplicate: false,
      ),
    );
    await auth.signOut();
    return result.patientId;
  }
}
