import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/data/permission_repository.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/shared/providers/session_context_loader.dart';

import 'fixture_factory.dart';
import 'live_supabase_harness.dart';
import 'reset.dart';
import 'sql_fixture_helper.dart';

/// Wired repositories + fixtures for boundary tests.
class BoundaryTestContext {
  BoundaryTestContext._(this.client)
    : auth = AuthRepositoryImpl(client),
      bootstrap = BootstrapRepositoryImpl(client),
      provisioning = ProvisioningRepositoryImpl(client),
      permissions = PermissionRepositoryImpl(client),
      organization = OrganizationRepositoryImpl(client),
      branches = BranchRepositoryImpl(client),
      staffAdmin = StaffAdminRepositoryImpl(client),
      rolePermissions = RolePermissionsRepositoryImpl(client),
      patients = PatientRepositoryImpl(client),
      sessionLoader = SessionContextLoader(client, PermissionRepositoryImpl(client)),
      fixtures = FixtureFactory(client),
      sql = SqlFixtureHelper();

  final SupabaseClient client;
  final AuthRepositoryImpl auth;
  final BootstrapRepositoryImpl bootstrap;
  final ProvisioningRepositoryImpl provisioning;
  final PermissionRepositoryImpl permissions;
  final OrganizationRepositoryImpl organization;
  final BranchRepositoryImpl branches;
  final StaffAdminRepositoryImpl staffAdmin;
  final RolePermissionsRepositoryImpl rolePermissions;
  final PatientRepositoryImpl patients;
  final SessionContextLoader sessionLoader;
  final FixtureFactory fixtures;
  final SqlFixtureHelper sql;

  BoundaryClinicFixture? clinic;

  static Future<BoundaryTestContext> create() async {
    await LiveSupabaseHarness.ensureReady();
    return BoundaryTestContext._(LiveSupabaseHarness.client);
  }

  /// Force-clears installation state. Per-test [setUp] calls this; clears cached clinic.
  Future<void> resetInstallation() async {
    await devResetAsBootstrapAdmin(client);
    clinic = null;
  }

  Future<BoundaryClinicFixture> ensureClinic({String? label}) async {
    final requested = label;
    if (clinic != null && (requested == null || clinic!.suffix == requested)) {
      return clinic!;
    }
    clinic = await fixtures.bootstrapOnly(label: requested);
    return clinic!;
  }

  Future<void> signInAdmin() async {
    await auth.signIn(username: 'admin', password: 'admin');
    await auth.refreshSession();
  }

  Future<void> signInStaff(String username, String password) async {
    await auth.signOut();
    await auth.signIn(username: username, password: password);
    await auth.refreshSession();
  }

  Future<void> signOut() => auth.signOut();

  /// Second org in the same test (SQL insert; bootstrap RPC allows only one org per installation).
  Future<BoundaryClinicFixture> bootstrapSecondaryClinic(String label) => sql.insertSecondaryClinic(label);
}
