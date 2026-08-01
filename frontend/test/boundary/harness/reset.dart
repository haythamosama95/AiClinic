import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/setup/data/bootstrap_repository.dart';

import 'boundary_test_context.dart';
import 'fixture_factory.dart';
import 'live_supabase_harness.dart';
import 'sql_fixture_helper.dart';

/// Serializes installation resets — boundary tests share one live database.
Future<void>? _resetChain;

Future<T> _serializedReset<T>(Future<T> Function() action) {
  final previous = _resetChain ?? Future<void>.value();
  final completer = Completer<void>();
  _resetChain = completer.future;
  return previous.then((_) => action()).whenComplete(() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
}

/// Signs in bootstrap admin, resets clinic data, signs out.
Future<void> devResetAsBootstrapAdmin(SupabaseClient client) {
  return _serializedReset(() async {
    await signOutIfNeeded(client);

    final auth = AuthRepositoryImpl(client);
    final bootstrap = BootstrapRepositoryImpl(client);
    final sql = SqlFixtureHelper();

    for (var attempt = 0; attempt < 3; attempt++) {
      await auth.signIn(username: 'admin', password: 'admin');
      await auth.refreshSession();

      try {
        final result = await bootstrap.resetInstallationForDevelopment();
        if (!result.success) {
          if (_resetNeedsSqlPurge(result.errorCode) && attempt < 2) {
            await sql.forcePurgeInstallation();
          } else {
            await auth.signOut();
            throw StateError('dev_reset failed: ${result.errorCode} ${result.errorMessage}');
          }
        }
      } on RpcFailure catch (error) {
        if (_resetNeedsSqlPurge(error.code) && attempt < 2) {
          await sql.forcePurgeInstallation();
        } else {
          await auth.signOut();
          rethrow;
        }
      }

      await sql.purgeProvisionedStaff();
      await sql.restoreDefaultRolePermissions();

      try {
        await sql.assertInstallationClean();
        break;
      } on StateError {
        if (attempt == 2) {
          rethrow;
        }
        await sql.forcePurgeInstallation();
      }

      await auth.signOut();
    }

    FixtureFactory.resetStaticState();
    await auth.signOut();
  });
}

bool _resetNeedsSqlPurge(String? code) =>
    code == 'RESET_DEPENDENCY_BLOCKED' || code == 'RESET_INCOMPLETE' || code == 'RESET_SAFE_DELETE';

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
