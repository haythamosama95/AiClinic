@Tags(['boundary', 'live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';

import '../harness/boundary_assertions.dart';
import '../harness/boundary_test_context.dart';
import '../harness/manifest_scenario.dart';
import '../harness/reset.dart';

void main() {
  late BoundaryTestContext ctx;

  setUpAll(() async {
    ctx = await BoundaryTestContext.create();
  });

  installBoundaryTestLifecycle(() => ctx);

  group('AuthRepositoryImpl', () {
    test('auth.signIn.success', () async {
      const ManifestScenario('auth.signIn.success');
      await ctx.signInAdmin();
      expect(ctx.auth.currentSession, isNotNull);
      expect(ctx.auth.currentUser?.email, 'admin');
    });

    test('auth.signIn.wrongPassword', () async {
      const ManifestScenario('auth.signIn.wrongPassword');
      expect(() => ctx.auth.signIn(username: 'admin', password: 'wrong-password'), throwsA(isA<AuthException>()));
    });

    test('auth.signIn.emptyCredentials', () async {
      const ManifestScenario('auth.signIn.emptyCredentials');
      expect(() => ctx.auth.signIn(username: ' ', password: ' '), throwsA(isA<AuthException>()));
    });

    test('auth.signOut.clearsSession', () async {
      const ManifestScenario('auth.signOut.clearsSession');
      await ctx.signInAdmin();
      await ctx.signOut();
      expect(ctx.auth.currentSession, isNull);
    });

    test('auth.refreshSession.afterBootstrap', () async {
      const ManifestScenario('auth.refreshSession.afterBootstrap');
      await ctx.ensureClinic(label: 'auth_refresh');
      await ctx.signInAdmin();
      await ctx.auth.refreshSession();
      expect(ctx.auth.currentSession, isNotNull);
    });

    test('auth.clearPersistedSessionOnColdStart', () async {
      const ManifestScenario('auth.clearPersistedSessionOnColdStart');
      await ctx.signInAdmin();
      await ctx.auth.clearPersistedSessionOnColdStart();
      expect(ctx.auth.currentSession, isNull);
    });

    test('auth.aggressive.signOutThenRpc', () async {
      const ManifestScenario('auth.aggressive.signOutThenRpc');
      final clinic = await ctx.ensureClinic(label: 'auth_signout_rpc');
      await ctx.signOut();
      await expectRpcCode(
        () => ctx.patients.searchPatients(scope: PatientListScope.thisBranch, branchId: clinic.branchId),
        'FORBIDDEN',
      );
    });

    test('auth.aggressive.switchUser', () async {
      const ManifestScenario('auth.aggressive.switchUser');
      final clinic = await ctx.ensureClinic(label: 'auth_switch');
      final doctor = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.doctor);
      final receptionist = await ctx.fixtures.createStaff(clinic: clinic, role: StaffRole.receptionist);
      await ctx.signInStaff(doctor.username, doctor.password);
      final doctorUser = ctx.auth.currentUser?.id;
      await ctx.signInStaff(receptionist.username, receptionist.password);
      expect(ctx.auth.currentUser?.id, isNot(equals(doctorUser)));
      expect(ctx.auth.currentSession, isNotNull);
    });
  });
}
