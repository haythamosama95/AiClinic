// Test-only helpers; not imported by production code.
// ignore_for_file: depend_on_referenced_packages

import 'package:ai_clinic/app/app.dart';
import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Valid local profile used by startup widget and integration tests.
DeploymentProfile sampleDeploymentProfile({String? sourcePath}) {
  return DeploymentProfile(
    deploymentMode: DeploymentMode.local,
    supabaseUrl: Uri.parse('http://127.0.0.1:54321'),
    supabaseAnonKey: 'test-anon-key',
    sourcePath: sourcePath ?? 'test/deployment-profile.json',
  );
}

StartupHealthResult sampleHealthResult({
  StartupConnectivityStatus status = StartupConnectivityStatus.healthy,
  DateTime? checkedAt,
}) {
  final checked = checkedAt ?? DateTime(2026, 5, 16, 12);
  final checks = [
    StartupDependencyCheck(
      name: 'gateway',
      uri: Uri.parse('http://127.0.0.1:54321'),
      reachable: status != StartupConnectivityStatus.unreachable,
      statusCode: 200,
      detail: 'HTTP 200',
    ),
    StartupDependencyCheck(
      name: 'auth',
      uri: Uri.parse('http://127.0.0.1:54321/auth/v1/health'),
      reachable: status == StartupConnectivityStatus.healthy || status == StartupConnectivityStatus.degraded,
      statusCode: status == StartupConnectivityStatus.degraded ? 503 : 200,
      detail: status == StartupConnectivityStatus.degraded ? 'HTTP 503' : 'HTTP 200',
    ),
    StartupDependencyCheck(
      name: 'rest',
      uri: Uri.parse('http://127.0.0.1:54321/rest/v1/'),
      reachable: status == StartupConnectivityStatus.healthy,
      statusCode: status == StartupConnectivityStatus.healthy ? 200 : 503,
      detail: status == StartupConnectivityStatus.healthy ? 'HTTP 200' : 'HTTP 503',
    ),
  ];

  return StartupHealthResult(status: status, checkedAt: checked, checks: checks);
}

class FakeDeploymentProfileStore extends DeploymentProfileStore {
  FakeDeploymentProfileStore({this.profile, this.error});

  final DeploymentProfile? profile;
  final DeploymentProfileException? error;

  @override
  Future<DeploymentProfile> load({String? overridePath}) async {
    if (error != null) {
      throw error!;
    }

    return profile ?? sampleDeploymentProfile();
  }
}

class FakeStartupHealthService extends StartupHealthService {
  FakeStartupHealthService(this.result);

  final StartupHealthResult result;

  @override
  Future<StartupHealthResult> check(SupabaseConfig config) async => result;
}

/// Boots the full app with deterministic startup dependencies for tests.
Future<void> pumpStartupApp(
  WidgetTester tester, {
  DeploymentProfile? profile,
  DeploymentProfileException? profileError,
  StartupHealthResult? healthResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deploymentProfileStoreProvider.overrideWithValue(
          FakeDeploymentProfileStore(profile: profile, error: profileError),
        ),
        startupHealthServiceProvider.overrideWithValue(FakeStartupHealthService(healthResult ?? sampleHealthResult())),
      ],
      child: const AiClinicApp(),
    ),
  );
}

/// Completes bootstrap and settles router redirects for integration scenarios.
Future<void> completeStartupBootstrap(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}
