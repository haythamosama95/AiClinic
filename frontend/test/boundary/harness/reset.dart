import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/data/bootstrap_repository.dart';

import 'boundary_test_context.dart';
import 'live_supabase_harness.dart';
import 'sql_fixture_helper.dart';

/// Signs in bootstrap admin, resets clinic data, signs out.
Future<void> devResetAsBootstrapAdmin(SupabaseClient client) async {
  final auth = AuthRepositoryImpl(client);
  final bootstrap = BootstrapRepositoryImpl(client);

  await auth.signIn(username: 'admin', password: 'admin');
  final result = await bootstrap.resetInstallationForDevelopment();
  if (!result.success) {
    throw StateError('dev_reset failed: ${result.errorCode} ${result.errorMessage}');
  }
  final sql = SqlFixtureHelper();
  await sql.purgeProvisionedStaff();
  await sql.restoreDefaultRolePermissions();
  await auth.signOut();
}

Future<void> signOutIfNeeded(SupabaseClient client) async {
  if (client.auth.currentSession != null) {
    await AuthRepositoryImpl(client).signOut();
  }
}

Future<void> boundarySetUpAll() => LiveSupabaseHarness.ensureReady();

Future<void> boundaryTearDown() => signOutIfNeeded(LiveSupabaseHarness.client);

/// Wipes clinic data via dev_reset + SQL purge (start/end of a boundary campaign).
Future<void> boundaryCampaignReset() => devResetAsBootstrapAdmin(LiveSupabaseHarness.client);

/// Per-test reset and sign-out hooks. Call from [main] after [setUpAll] creates [getCtx].
void installBoundaryTestLifecycle(BoundaryTestContext Function() getCtx) {
  setUp(() async {
    await getCtx().resetInstallation();
  });
  tearDown(() async {
    await getCtx().signOut();
  });
}
