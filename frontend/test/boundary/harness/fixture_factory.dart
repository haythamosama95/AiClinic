import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';

import 'reset.dart';

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
  String usernameFor(StaffRole role) {
    final prefix = 'bd_${role.wireValue}_';
    final maxTag = 32 - prefix.length;
    final tag = '$seq';
    return '$prefix${tag.length <= maxTag ? tag : tag.substring(0, maxTag)}';
  }
}

class FixtureFactory {
  FixtureFactory(this.client);

  final SupabaseClient client;

  static int _counter = 0;
  static int _clinicSeq = 0;

  /// Bootstraps a fresh org + branch (caller must reset installation first).
  Future<BoundaryClinicFixture> bootstrapOnly({String? label}) async {
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

    await auth.refreshSession();
    await auth.signOut();

    return BoundaryClinicFixture(
      seq: seq,
      suffix: suffix,
      organizationId: orgId,
      branchId: branchId,
      organizationName: orgName,
      branchCode: branchCode,
    );
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
    } else {
      final creds = await createStaff(clinic: clinic, role: asRole);
      await auth.signIn(username: creds.username, password: creds.password);
    }
    await auth.refreshSession();

    final repo = PatientRepositoryImpl(client);
    final id = await repo.createPatient(
      CreatePatientInput(
        activeBranchId: clinic.branchId,
        fullName: fullName ?? 'Patient ${clinic.suffix}',
        phone: phone ?? clinic.phone(),
        dateOfBirth: dateOfBirth,
        acknowledgeDuplicate: acknowledgeDuplicate,
      ),
    );

    await auth.signOut();
    return id;
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
    await auth.refreshSession();

    final repo = PatientRepositoryImpl(client);
    final id = await repo.createPatient(
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
    return id;
  }
}
