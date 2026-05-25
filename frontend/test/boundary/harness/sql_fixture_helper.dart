import 'dart:io';

import 'fixture_factory.dart';

/// Runs one-off SQL against local Postgres for states RPCs cannot set (revocation, inactive staff).
class SqlFixtureHelper {
  static const _bootstrapUserId = 'a0000000-0000-4000-8000-000000000001';
  SqlFixtureHelper({
    this.host = '127.0.0.1',
    this.port = 54322,
    this.user = 'postgres',
    this.database = 'postgres',
    String? password,
  }) : password = password ?? Platform.environment['POSTGRES_PASSWORD'] ?? 'postgres';

  final String host;
  final int port;
  final String user;
  final String database;
  final String password;

  Future<void> execute(String sql) async {
    final result = await Process.run(
      'psql',
      ['-h', host, '-p', '$port', '-U', user, '-d', database, '-v', 'ON_ERROR_STOP=1', '-c', sql],
      environment: {'PGPASSWORD': password},
    );

    if (result.exitCode != 0) {
      throw StateError('psql failed (${result.exitCode}): ${result.stderr}\nSQL: $sql');
    }
  }

  /// Verifies dev_reset is FORBIDDEN when app.environment=production (same session as RPC).
  Future<void> expectDevResetForbiddenInProduction() async {
    await execute(r'''
DO $$
DECLARE
  v_result public.rpc_result;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('app.environment', 'production', true);
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', 'a0000000-0000-4000-8000-000000000001',
      'role', 'authenticated'
    )::text,
    true
  );

  v_result := public.dev_reset_clinic_installation();
  IF v_result.success OR v_result.error_code <> 'FORBIDDEN' THEN
    RAISE EXCEPTION 'expected FORBIDDEN, got %', COALESCE(v_result.error_code, 'success');
  END IF;

  PERFORM set_config('app.environment', 'development', true);
END;
$$;
''');
  }

  static String _deterministicUuid(String prefix, String label) {
    final hash = '$prefix$label'.hashCode.abs();
    final p1 = hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
    final p2 = (hash >> 4).toRadixString(16).padLeft(4, '0').substring(0, 4);
    final p3 = (hash >> 8).toRadixString(16).padLeft(3, '0').substring(0, 3);
    final p4 = (hash >> 12).toRadixString(16).padLeft(3, '0').substring(0, 3);
    final p5 = hash.toRadixString(16).padLeft(12, '0').substring(0, 12);
    return '$p1-$p2-4$p3-8$p4-$p5';
  }

  /// Second tenant for cross-org RLS tests (bootstrap RPC allows only one org per installation).
  Future<BoundaryClinicFixture> insertSecondaryClinic(String label) async {
    final suffix = label;
    final orgId = _deterministicUuid('c2', suffix);
    final branchId = _deterministicUuid('d2', suffix);
    final orgName = 'Boundary Iso Org $suffix';
    final branchCode = 'ISO${suffix.hashCode.abs() % 100000}';

    await execute('''
INSERT INTO public.organizations (id, name, created_by, updated_by)
VALUES ('$orgId'::uuid, '$orgName', '$_bootstrapUserId'::uuid, '$_bootstrapUserId'::uuid)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.branches (id, organization_id, name, code, created_by, updated_by)
VALUES (
  '$branchId'::uuid,
  '$orgId'::uuid,
  'Iso Branch $suffix',
  '$branchCode',
  '$_bootstrapUserId'::uuid,
  '$_bootstrapUserId'::uuid
)
ON CONFLICT (id) DO NOTHING;
''');

    return BoundaryClinicFixture(
      seq: 0,
      suffix: suffix,
      organizationId: orgId,
      branchId: branchId,
      organizationName: orgName,
      branchCode: branchCode,
    );
  }

  Future<String> insertPatient({
    required BoundaryClinicFixture clinic,
    required String fullName,
    required String phoneDigits,
  }) async {
    final patientId = _deterministicUuid('a2', '${clinic.suffix}_patient');
    await execute('''
INSERT INTO public.patients (
  id, branch_id, organization_id, full_name, phone, created_by, updated_by
)
VALUES (
  '$patientId'::uuid,
  '${clinic.branchId}'::uuid,
  '${clinic.organizationId}'::uuid,
  '$fullName',
  '$phoneDigits',
  '$_bootstrapUserId'::uuid,
  '$_bootstrapUserId'::uuid
)
ON CONFLICT (id) DO NOTHING;
''');
    return patientId;
  }

  /// Staff row in another org (admin JWT from org A must not read it via PostgREST).
  Future<({String staffMemberId})> insertStaffMember({
    required BoundaryClinicFixture clinic,
    String role = 'doctor',
    String fullName = 'Iso Staff',
  }) async {
    final authUserId = _deterministicUuid('e2', '${clinic.suffix}_auth');
    final staffMemberId = _deterministicUuid('f2', '${clinic.suffix}_staff');
    final email = 'iso_${clinic.suffix.hashCode.abs()}@boundary.test';

    await execute('''
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
VALUES (
  '$authUserId'::uuid,
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  '$email',
  extensions.crypt('TestPass1', extensions.gen_salt('bf')),
  now(), now(), now()
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.staff_members (id, auth_user_id, full_name, role, created_by, updated_by)
VALUES (
  '$staffMemberId'::uuid,
  '$authUserId'::uuid,
  '$fullName',
  '$role',
  '$_bootstrapUserId'::uuid,
  '$_bootstrapUserId'::uuid
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.staff_branch_assignments (staff_member_id, branch_id, is_primary, created_by, updated_by)
VALUES (
  '$staffMemberId'::uuid,
  '${clinic.branchId}'::uuid,
  true,
  '$_bootstrapUserId'::uuid,
  '$_bootstrapUserId'::uuid
)
ON CONFLICT (staff_member_id, branch_id) DO NOTHING;
''');

    return (staffMemberId: staffMemberId);
  }

  Future<void> deactivateStaff(String staffMemberId) async {
    await execute("UPDATE public.staff_members SET is_active = false WHERE id = '$staffMemberId'::uuid;");
  }

  Future<void> revokePermission({required String role, required String permissionKey}) async {
    await execute(
      "UPDATE public.roles_permissions SET is_granted = false, updated_at = now() "
      "WHERE role = '$role' AND permission_key = '$permissionKey' AND is_deleted = false;",
    );
  }

  Future<void> grantPermission({required String role, required String permissionKey}) async {
    await execute(
      "UPDATE public.roles_permissions SET is_granted = true, updated_at = now() "
      "WHERE role = '$role' AND permission_key = '$permissionKey' AND is_deleted = false;",
    );
  }

  /// Resets global role permission rows mutated by boundary tests.
  Future<void> restoreDefaultRolePermissions() async {
    await execute('''
UPDATE public.roles_permissions SET is_granted = true, updated_at = now()
WHERE role IN ('owner', 'administrator', 'doctor', 'receptionist')
  AND permission_key IN ('patients.view', 'patients.create', 'patients.edit', 'patients.delete')
  AND is_deleted = false;
UPDATE public.roles_permissions SET is_granted = true, updated_at = now()
WHERE role = 'lab_staff' AND permission_key = 'patients.view' AND is_deleted = false;
UPDATE public.roles_permissions SET is_granted = false, updated_at = now()
WHERE role = 'lab_staff'
  AND permission_key IN ('patients.create', 'patients.edit', 'patients.delete')
  AND is_deleted = false;
''');
  }

  /// Removes provisioned staff/auth users left by [dev_reset] (orgs/branches only).
  Future<void> purgeProvisionedStaff() async {
    await execute('''
DELETE FROM public.staff_branch_assignments sba
WHERE sba.staff_member_id IN (
  SELECT id FROM public.staff_members WHERE NOT is_bootstrap_admin
);
''');
    await execute('''
DELETE FROM public.staff_members WHERE NOT is_bootstrap_admin;
''');
    await execute('''
DELETE FROM auth.users au
WHERE NOT EXISTS (
  SELECT 1 FROM public.staff_members sm WHERE sm.auth_user_id = au.id
);
''');
  }
}
